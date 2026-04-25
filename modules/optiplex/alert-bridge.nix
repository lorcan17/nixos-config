{ domain, pkgs, ... }:

let
  port = 9099;

  bridge = pkgs.writeScript "alert-bridge.py" ''
    #!${pkgs.python3}/bin/python3
    import json, urllib.request
    from http.server import BaseHTTPRequestHandler, HTTPServer

    NTFY_URL = "https://ntfy.${domain}/alerts"

    def shape(payload):
        ann   = payload.get("commonAnnotations", {}) or {}
        lbls  = payload.get("commonLabels", {}) or {}
        state = (payload.get("status") or "firing").lower()

        title = lbls.get("alertname") or payload.get("title", "alert")
        summary = ann.get("summary") or payload.get("message", "")
        desc    = ann.get("description", "")
        body    = summary + (" — " + desc if desc and desc not in summary else "")

        priority = "default" if state == "resolved" else "high"
        tags     = "white_check_mark,optiplex" if state == "resolved" else "warning,optiplex"
        return title.strip(), (body or "alert").strip(), priority, tags

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(n)
            try:
                payload = json.loads(raw)
                title, body, priority, tags = shape(payload)
                req = urllib.request.Request(
                    NTFY_URL,
                    data=body.encode("utf-8"),
                    headers={
                        "Title":    title,
                        "Priority": priority,
                        "Tags":     tags,
                    },
                    method="POST",
                )
                urllib.request.urlopen(req, timeout=5).read()
                self.send_response(204); self.end_headers()
            except Exception as e:
                self.send_response(502); self.end_headers()
                self.wfile.write(str(e).encode())

        def log_message(self, fmt, *a):
            print("alert-bridge: " + fmt % a, flush=True)

    HTTPServer(("127.0.0.1", ${toString port}), H).serve_forever()
  '';
in
{
  systemd.services.alert-bridge = {
    description = "Translate Grafana webhook JSON into clean ntfy push notifications";
    wantedBy = [ "multi-user.target" ];
    after    = [ "network.target" ];
    serviceConfig = {
      ExecStart        = "${bridge}";
      DynamicUser      = true;
      Restart          = "on-failure";
      RestartSec       = 5;
      NoNewPrivileges  = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
      PrivateTmp       = true;
    };
  };
}
