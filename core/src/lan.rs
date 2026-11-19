//! iPhone ↔ Android battles over the same Wi‑Fi or a phone's hotspot. No server, no internet.
//!
//! Each phone listens on a TCP port and puts its local addresses into its duel QR code. The phone
//! that scans connects to the other one. Messages are newline-delimited JSON (the battle protocol
//! itself is owned by the apps); this layer handles the handshake, keep-alive pings, drop detection
//! and automatic reconnects, and is shared by both apps through UniFFI.

use std::io::{BufRead, BufReader, ErrorKind, Write};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

// ---------- QR codes ----------

pub const QR_PREFIX: &str = "meitian-duel:";

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct DuelQrInfo {
    pub player_id: String,
    /// "ios", "android", or "" for codes from older app versions.
    pub os: String,
    /// Local IPv4 addresses of the phone that showed the code.
    pub addrs: Vec<String>,
    pub port: u16,
}

/// `meitian-duel:<id>?os=ios&lan=192.168.1.5,172.20.10.1&port=51234`
#[uniffi::export]
pub fn duel_qr_payload(player_id: String, os: String, addrs: Vec<String>, port: u16) -> String {
    if addrs.is_empty() || port == 0 {
        return format!("{QR_PREFIX}{player_id}?os={os}");
    }
    format!("{QR_PREFIX}{player_id}?os={os}&lan={}&port={port}", addrs.join(","))
}

/// Parses new and old ("meitian-duel:<id>") codes. `None` if it isn't a duel code.
#[uniffi::export]
pub fn parse_duel_qr(code: String) -> Option<DuelQrInfo> {
    let rest = code.trim().strip_prefix(QR_PREFIX)?;
    let (id, query) = rest.split_once('?').unwrap_or((rest, ""));
    let id = id.trim();
    let hex = id.chars().filter(|c| c.is_ascii_hexdigit()).count();
    if hex != 32 || !id.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
        return None;
    }
    let mut info = DuelQrInfo { player_id: id.to_string(), os: String::new(), addrs: vec![], port: 0 };
    for pair in query.split('&') {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        match k {
            "os" => info.os = v.to_string(),
            "lan" => info.addrs = v.split(',').filter(|a| a.parse::<Ipv4Addr>().is_ok()).map(String::from).collect(),
            "port" => info.port = v.parse().unwrap_or(0),
            _ => {}
        }
    }
    Some(info)
}

// ---------- local addresses ----------

fn is_private(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    o[0] == 10 || (o[0] == 172 && (16..=31).contains(&o[1])) || (o[0] == 192 && o[1] == 168)
}

/// Local IPv4 addresses another phone on the same Wi‑Fi / hotspot can reach, best first
/// (Wi‑Fi and hotspot interfaces; cellular and VPN interfaces are skipped).
#[uniffi::export]
pub fn lan_addresses() -> Vec<String> {
    let mut out: Vec<(u8, String)> = Vec::new();
    #[cfg(unix)]
    unsafe {
        let mut ifap: *mut libc::ifaddrs = std::ptr::null_mut();
        if libc::getifaddrs(&mut ifap) == 0 {
            let mut cur = ifap;
            while !cur.is_null() {
                let ifa = &*cur;
                cur = ifa.ifa_next;
                if ifa.ifa_addr.is_null() || (*ifa.ifa_addr).sa_family as i32 != libc::AF_INET {
                    continue;
                }
                let name = std::ffi::CStr::from_ptr(ifa.ifa_name).to_string_lossy().to_string();
                let sin = &*(ifa.ifa_addr as *const libc::sockaddr_in);
                let ip = Ipv4Addr::from(u32::from_be(sin.sin_addr.s_addr));
                if ip.is_loopback() || !is_private(ip) {
                    continue;
                }
                let skip = ["pdp_ip", "rmnet", "ccmni", "utun", "ipsec", "tun", "ppp", "v4-", "clat"];
                if skip.iter().any(|s| name.starts_with(s)) {
                    continue;
                }
                // Wi‑Fi first, then hotspot / bridges, then anything else private
                let rank = if name.starts_with("en") || name.starts_with("wlan") { 0 }
                    else if name.starts_with("bridge") || name.starts_with("ap") || name.starts_with("swlan") { 1 }
                    else { 2 };
                let s = ip.to_string();
                if !out.iter().any(|(_, a)| *a == s) {
                    out.push((rank, s));
                }
            }
            libc::freeifaddrs(ifap);
        }
    }
    out.sort_by_key(|(r, _)| *r);
    out.into_iter().map(|(_, a)| a).take(4).collect()
}

// ---------- the link ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum LanState {
    Idle,
    /// Waiting for the other phone (listening; or still trying to reach it after a scan).
    Listening,
    Connecting,
    Connected,
    Reconnecting,
    /// A scan couldn't reach the other phone for a while (still retrying in the background).
    Unreachable,
}

/// Events from the link. Called on a background thread: hop to the main thread in the app.
#[uniffi::export(with_foreign)]
pub trait LanListener: Send + Sync {
    fn on_state(&self, state: LanState);
    fn on_message(&self, json: String);
}

const PING_EVERY: Duration = Duration::from_millis(1500);
const DEAD_AFTER: Duration = Duration::from_secs(6);

struct Inner {
    my_id: String,
    listener: Arc<dyn LanListener>,
    writer: Mutex<Option<TcpStream>>,
    partner: Mutex<Option<String>>,
    /// Set when we scanned the other phone: where to (re)connect and whom we expect.
    target: Mutex<Option<(Vec<SocketAddr>, String)>>,
    state: Mutex<LanState>,
    stopped: AtomicBool,
    generation: AtomicU64,
    joining: AtomicBool,
    last_rx: Mutex<Instant>,
}

impl Inner {
    fn set_state(&self, s: LanState) {
        let mut cur = self.state.lock().unwrap();
        if *cur != s {
            *cur = s;
            drop(cur);
            self.listener.on_state(s);
        }
    }

    fn state(&self) -> LanState {
        *self.state.lock().unwrap()
    }

    fn write_line(stream: &mut TcpStream, line: &str) -> std::io::Result<()> {
        let mut buf = line.as_bytes().to_vec();
        buf.push(b'\n');
        stream.write_all(&buf)
    }

    /// A handshaken connection becomes the active one; any older connection is dropped.
    fn attach(self: &Arc<Self>, stream: TcpStream, partner: String) {
        let generation = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        let _ = stream.set_nodelay(true);
        let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
        let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
        let Ok(reader) = stream.try_clone() else { return };
        if let Some(old) = self.writer.lock().unwrap().replace(stream) {
            let _ = old.shutdown(std::net::Shutdown::Both);
        }
        *self.partner.lock().unwrap() = Some(partner);
        *self.last_rx.lock().unwrap() = Instant::now();
        self.set_state(LanState::Connected);

        let me = Arc::clone(self);
        thread::spawn(move || me.read_loop(reader, generation));
    }

    fn read_loop(self: Arc<Self>, stream: TcpStream, generation: u64) {
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        loop {
            if self.stopped.load(Ordering::SeqCst) || self.generation.load(Ordering::SeqCst) != generation {
                return;
            }
            match reader.read_line(&mut line) {
                Ok(0) => break, // closed
                Ok(_) => {
                    *self.last_rx.lock().unwrap() = Instant::now();
                    let msg = line.trim();
                    if !msg.is_empty() && !msg.starts_with("{\"t\":\"ping\"") {
                        self.listener.on_message(msg.to_string());
                    }
                    line.clear();
                }
                Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                    // keep any partial line in `line`; just check liveness
                    if self.last_rx.lock().unwrap().elapsed() > DEAD_AFTER {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        // only the current connection may report a drop
        if self.generation.load(Ordering::SeqCst) == generation && !self.stopped.load(Ordering::SeqCst) {
            if let Some(w) = self.writer.lock().unwrap().take() {
                let _ = w.shutdown(std::net::Shutdown::Both);
            }
            self.set_state(LanState::Reconnecting);
            if self.target.lock().unwrap().is_some() {
                self.spawn_join();
            }
        }
    }

    fn handle_incoming(self: &Arc<Self>, stream: TcpStream) {
        let mut stream = stream;
        let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
        let Some(line) = read_handshake(&mut stream) else { return };
        let Some((id, want)) = parse_hello(&line) else { return };
        let partner = self.partner.lock().unwrap().clone();
        // only someone who scanned *my* code (and, once paired, only my partner) may connect
        if want != self.my_id || partner.as_ref().is_some_and(|p| *p != id) || id == self.my_id {
            return;
        }
        let mut s = stream;
        if Self::write_line(&mut s, &format!("{{\"t\":\"lan-ok\",\"id\":\"{}\"}}", self.my_id)).is_err() {
            return;
        }
        self.attach(s, id);
    }

    fn spawn_join(self: &Arc<Self>) {
        if self.joining.swap(true, Ordering::SeqCst) {
            return; // a join loop is already running
        }
        let me = Arc::clone(self);
        thread::spawn(move || {
            let started = Instant::now();
            while !me.stopped.load(Ordering::SeqCst) && me.state() != LanState::Connected {
                let Some((addrs, want)) = me.target.lock().unwrap().clone() else { break };
                for addr in &addrs {
                    if me.stopped.load(Ordering::SeqCst) || me.state() == LanState::Connected {
                        break;
                    }
                    if let Some(stream) = me.try_join(addr, &want) {
                        me.attach(stream, want.clone());
                        break;
                    }
                }
                if me.state() != LanState::Connected {
                    if started.elapsed() > Duration::from_secs(7) && me.state() == LanState::Connecting {
                        me.set_state(LanState::Unreachable);
                    }
                    thread::sleep(Duration::from_millis(1200));
                }
            }
            me.joining.store(false, Ordering::SeqCst);
        });
    }

    fn try_join(&self, addr: &SocketAddr, want: &str) -> Option<TcpStream> {
        let mut s = TcpStream::connect_timeout(addr, Duration::from_millis(1500)).ok()?;
        s.set_read_timeout(Some(Duration::from_secs(3))).ok()?;
        s.set_write_timeout(Some(Duration::from_secs(2))).ok()?;
        Self::write_line(&mut s, &format!("{{\"t\":\"lan-hi\",\"id\":\"{}\",\"want\":\"{}\"}}", self.my_id, want)).ok()?;
        let line = read_handshake(&mut s)?;
        let v: serde_json::Value = serde_json::from_str(line.trim()).ok()?;
        (v["t"] == "lan-ok" && v["id"] == want).then_some(s)
    }
}

/// Reads one handshake line byte by byte, so nothing after it is swallowed into a buffer
/// (the app's first messages can arrive right behind the handshake).
fn read_handshake(stream: &mut TcpStream) -> Option<String> {
    use std::io::Read;
    let mut out = Vec::new();
    let mut b = [0u8; 1];
    while out.len() < 512 {
        match stream.read(&mut b) {
            Ok(1) if b[0] == b'\n' => return String::from_utf8(out).ok(),
            Ok(1) => out.push(b[0]),
            _ => return None,
        }
    }
    None
}

fn parse_hello(line: &str) -> Option<(String, String)> {
    let v: serde_json::Value = serde_json::from_str(line.trim()).ok()?;
    if v["t"] != "lan-hi" {
        return None;
    }
    Some((v["id"].as_str()?.to_string(), v["want"].as_str()?.to_string()))
}

#[derive(uniffi::Object)]
pub struct LanLink {
    inner: Arc<Inner>,
    port: Mutex<u16>,
}

#[uniffi::export]
impl LanLink {
    #[uniffi::constructor]
    pub fn new(my_id: String, listener: Arc<dyn LanListener>) -> Arc<Self> {
        let inner = Arc::new(Inner {
            my_id,
            listener,
            writer: Mutex::new(None),
            partner: Mutex::new(None),
            target: Mutex::new(None),
            state: Mutex::new(LanState::Idle),
            stopped: AtomicBool::new(false),
            generation: AtomicU64::new(0),
            joining: AtomicBool::new(false),
            last_rx: Mutex::new(Instant::now()),
        });
        // keep-alive pings
        let weak = Arc::downgrade(&inner);
        thread::spawn(move || loop {
            thread::sleep(PING_EVERY);
            let Some(me) = weak.upgrade() else { return };
            if me.stopped.load(Ordering::SeqCst) {
                return;
            }
            let mut guard = me.writer.lock().unwrap();
            if let Some(w) = guard.as_mut() {
                let _ = Inner::write_line(w, "{\"t\":\"ping\"}");
            }
            drop(guard);
        });
        Arc::new(LanLink { inner, port: Mutex::new(0) })
    }

    /// Start accepting the other phone. Returns the port for the QR code (0 if listening failed).
    pub fn listen(&self) -> u16 {
        if *self.port.lock().unwrap() != 0 {
            return *self.port.lock().unwrap();
        }
        let Ok(listener) = TcpListener::bind(SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 0)) else { return 0 };
        let port = listener.local_addr().map(|a| a.port()).unwrap_or(0);
        if listener.set_nonblocking(true).is_err() {
            return 0;
        }
        *self.port.lock().unwrap() = port;
        if self.inner.state() == LanState::Idle {
            self.inner.set_state(LanState::Listening);
        }
        let inner = Arc::clone(&self.inner);
        thread::spawn(move || {
            while !inner.stopped.load(Ordering::SeqCst) {
                match listener.accept() {
                    Ok((stream, _)) => {
                        let _ = stream.set_nonblocking(false);
                        let me = Arc::clone(&inner);
                        thread::spawn(move || me.handle_incoming(stream));
                    }
                    Err(e) if e.kind() == ErrorKind::WouldBlock => thread::sleep(Duration::from_millis(60)),
                    Err(_) => thread::sleep(Duration::from_millis(200)),
                }
            }
        });
        port
    }

    /// Connect to the phone whose QR code was scanned (tries each address, keeps retrying).
    pub fn join(&self, addrs: Vec<String>, port: u16, player_id: String) {
        let sockets: Vec<SocketAddr> = addrs
            .iter()
            .filter_map(|a| a.parse::<Ipv4Addr>().ok())
            .map(|ip| SocketAddr::new(IpAddr::V4(ip), port))
            .collect();
        if sockets.is_empty() || port == 0 {
            self.inner.set_state(LanState::Unreachable);
            return;
        }
        *self.inner.target.lock().unwrap() = Some((sockets, player_id));
        if self.inner.state() != LanState::Connected {
            self.inner.set_state(LanState::Connecting);
            self.inner.spawn_join();
        }
    }

    /// Send one message (a JSON object, no newlines).
    pub fn send(&self, json: String) {
        let line = json.replace('\n', " ");
        let mut guard = self.inner.writer.lock().unwrap();
        if let Some(w) = guard.as_mut() {
            if Inner::write_line(w, &line).is_err() {
                let _ = w.shutdown(std::net::Shutdown::Both); // the reader notices and reconnects
            }
        }
    }

    pub fn state(&self) -> LanState {
        self.inner.state()
    }

    pub fn is_connected(&self) -> bool {
        self.inner.state() == LanState::Connected
    }

    pub fn stop(&self) {
        self.inner.stopped.store(true, Ordering::SeqCst);
        if let Some(w) = self.inner.writer.lock().unwrap().take() {
            let _ = w.shutdown(std::net::Shutdown::Both);
        }
        *self.inner.state.lock().unwrap() = LanState::Idle;
    }
}

impl Drop for LanLink {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    #[test]
    fn qr_round_trip() {
        let id = "7C9E6679-7425-40DE-944B-E07FC1F90AE7".to_string();
        let code = duel_qr_payload(id.clone(), "ios".into(), vec!["192.168.1.5".into(), "172.20.10.1".into()], 51234);
        let info = parse_duel_qr(code).unwrap();
        assert_eq!(info.player_id, id);
        assert_eq!(info.os, "ios");
        assert_eq!(info.addrs, vec!["192.168.1.5", "172.20.10.1"]);
        assert_eq!(info.port, 51234);
        // codes from older versions
        let old = parse_duel_qr("meitian-duel:7c9e6679-7425-40de-944b-e07fc1f90ae7".into()).unwrap();
        assert_eq!(old.os, "");
        assert!(old.addrs.is_empty());
        assert!(parse_duel_qr("hello".into()).is_none());
        assert!(parse_duel_qr("meitian-duel:nope".into()).is_none());
    }

    #[test]
    fn private_ranges() {
        assert!(is_private("192.168.0.2".parse().unwrap()));
        assert!(is_private("172.20.10.1".parse().unwrap()));
        assert!(is_private("10.1.2.3".parse().unwrap()));
        assert!(!is_private("8.8.8.8".parse().unwrap()));
        let _ = lan_addresses(); // must not crash
    }

    struct Probe {
        states: Mutex<mpsc::Sender<LanState>>,
        msgs: Mutex<mpsc::Sender<String>>,
    }
    impl LanListener for Probe {
        fn on_state(&self, s: LanState) {
            let _ = self.states.lock().unwrap().send(s);
        }
        fn on_message(&self, json: String) {
            let _ = self.msgs.lock().unwrap().send(json);
        }
    }

    fn probe() -> (Arc<Probe>, mpsc::Receiver<LanState>, mpsc::Receiver<String>) {
        let (st, sr) = mpsc::channel();
        let (mt, mr) = mpsc::channel();
        (Arc::new(Probe { states: Mutex::new(st), msgs: Mutex::new(mt) }), sr, mr)
    }

    fn wait_for(rx: &mpsc::Receiver<LanState>, want: LanState) {
        let deadline = Instant::now() + Duration::from_secs(10);
        while Instant::now() < deadline {
            if let Ok(s) = rx.recv_timeout(Duration::from_millis(200)) {
                if s == want {
                    return;
                }
            }
        }
        panic!("never reached {want:?}");
    }

    #[test]
    fn loopback_match_with_reconnect() {
        let (pa, sa, ma) = probe();
        let (pb, sb, mb) = probe();
        let a = LanLink::new("aaaaaaaa-0000-0000-0000-000000000000".into(), pa);
        let b = LanLink::new("bbbbbbbb-0000-0000-0000-000000000000".into(), pb);
        let port = a.listen();
        assert!(port > 0);
        b.listen();

        // a stranger asking for someone else is refused
        let (pc, sc, _mc) = probe();
        let c = LanLink::new("cccccccc-0000-0000-0000-000000000000".into(), pc);
        c.join(vec!["127.0.0.1".into()], port, "dddddddd-0000-0000-0000-000000000000".into());
        assert!(sc.recv_timeout(Duration::from_secs(9)).map(|s| s != LanState::Connected).unwrap_or(true));
        c.stop();

        b.join(vec!["10.255.255.1".into(), "127.0.0.1".into()], port, "aaaaaaaa-0000-0000-0000-000000000000".into());
        wait_for(&sa, LanState::Connected);
        wait_for(&sb, LanState::Connected);

        // a scripted exchange both ways
        b.send(r#"{"t":"hello","card":{"id":"b"}}"#.into());
        assert_eq!(ma.recv_timeout(Duration::from_secs(3)).unwrap(), r#"{"t":"hello","card":{"id":"b"}}"#);
        for i in 0..20 {
            a.send(format!(r#"{{"t":"round","i":{i}}}"#));
        }
        for i in 0..20 {
            assert_eq!(mb.recv_timeout(Duration::from_secs(3)).unwrap(), format!(r#"{{"t":"round","i":{i}}}"#));
        }

        // kill the connection under them: the joiner reconnects by itself
        if let Some(w) = a.inner.writer.lock().unwrap().as_ref() {
            let _ = w.shutdown(std::net::Shutdown::Both);
        }
        wait_for(&sb, LanState::Reconnecting);
        wait_for(&sb, LanState::Connected);
        b.send(r#"{"t":"answer","i":3,"ok":true,"ms":900}"#.into());
        let got = (0..10).find_map(|_| ma.recv_timeout(Duration::from_secs(2)).ok().filter(|m| m.contains("answer")));
        assert!(got.is_some(), "messages flow after the reconnect");
        a.stop();
        b.stop();
    }
}
