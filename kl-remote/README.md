# Hosting qiita-web on kl-remote

Serves the qiita-web SPA from kl-remote against the barnacle dev stack, which moves between nodes when it restarts.
Same shape as the mimo gateway: a 2-minute timer finds the node, an ssh forward follows it.

```
browser ─▶ cloudflared ─▶ oauth2-proxy ─▶ Caddy 127.0.0.1:8187 ─┬─ /api/* ─▶ 127.0.0.1:18080 ─▶ qiita-tunnel (ssh -J barnacle) ─▶ <node>:127.0.0.1:18080
                                                                └─ SPA build/
qiita-node.timer (2 min) ─▶ qiita-node.sh: newest running qiita-dev-stack job that is up and answers /healthz ─▶ tunnel-qiita.env, restart the tunnel
```

- `qiita-node.sh` only follows the stack. `stack/watch-stack.sh` on barnacle owns restarts, so two controllers never fight.
- The tunnel hops onto the stack's node and forwards to its loopback, so it works whether the control plane binds
  `127.0.0.1` or `0.0.0.0`. barnacle allows ssh into a node where you have a running job.
- No new ports open on the LAN: Caddy and the tunnel bind 127.0.0.1.
- The dev stack has no login (AuthRocket off), so users paste a personal token after the Google gate.

## Install (each step is a write on kl-remote: run it only with the owner's go-ahead)

1. A key of the stack owner's: kl-remote's existing `Host barnacle` is another user's identity, and only the job's owner
   may ssh into its node.
   ```bash
   ssh-keygen -t ed25519 -N '' -C 'kl-remote qiita-node' -f ~/.ssh/barnacle_jokirkland_ed25519
   cat ssh_config.snippet >> ~/.ssh/config
   ```
   Append the `.pub` to `~/.ssh/authorized_keys` on barnacle (shared home, so it covers the compute nodes too), then
   check `ssh barnacle-jk true` and `ssh <current node> true`.
2. Files:
   ```bash
   mkdir -p ~/qiita-node ~/.config/qiita-node
   cp qiita-node.sh ~/qiita-node/ && chmod +x ~/qiita-node/qiita-node.sh
   cp qiita-node.env.example ~/.config/qiita-node/qiita-node.env   # check LOCAL_PORT is free: ss -ltn
   cp systemd/qiita-node.{service,timer} systemd/qiita-tunnel.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   ~/qiita-node/qiita-node.sh            # first run writes tunnel-qiita.env and starts the tunnel
   systemctl --user enable --now qiita-node.timer
   systemctl --user enable qiita-tunnel.service
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18080/healthz   # expect 200
   ```
3. SPA: build from a pinned commit of `lucaspatel/feat/web-ui` (`cd qiita-web && npm ci && npm run build`) and copy
   `build/` to `~/qiita-web/build`. Only once the stack runs the control-plane routes the UI needs.
4. Caddy: add `Caddyfile.snippet`, validate, reload.
5. Expose: a hostname on the `qiita-explore` tunnel behind oauth2-proxy (same pattern as the other gated hostnames).

Logs: `journalctl --user -u qiita-node -u qiita-tunnel`.
Undo: `systemctl --user disable --now qiita-node.timer qiita-tunnel.service`, remove the units and the Caddy block.
