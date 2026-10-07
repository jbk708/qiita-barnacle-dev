# qiita-barnacle-dev

A personal, throwaway [Qiita](https://github.com/the-miint/Qiita) stack on barnacle. One Slurm job hosts
Postgres (apptainer), the data plane, the control plane and the compute orchestrator on localhost. Downloads run in-process (`COMPUTE_BACKEND=local`), auth is one
master admin token (AuthRocket off), and nothing migrates to production.

Settings live in [`config.sh`](config.sh): `QDEV_ROOT` (stack), `QDEV_ACCOUNT` (required), `QDEV_EMAIL`. Override them in the environment.

## Spin up (first time)

On the barnacle login node:

```bash
git clone https://github.com/jbk708/qiita-barnacle-dev && cd qiita-barnacle-dev
export QDEV_ACCOUNT=<your Slurm account> && source config.sh
mkdir -p $QDEV_ROOT/{pg,pg-dumps,scratch,persistent,duckdb-ext,env,logs,cargo-home}
curl -LsSf https://astral.sh/uv/install.sh | sh                   # once; barnacle has no uv
git clone https://github.com/the-miint/Qiita $QDEV_ROOT/Qiita      # check out the branch to run
./stack/build.sh             # venvs, postgres + rust SIFs, data plane (~10 min on a short node)
./stack/bootstrap-env.sh     # after the build: writes env/ and generates keys, once
./stack/up.sh                # Postgres init, migrations, actions sync, miint, master token
```

`up.sh` defaults to `long` (14 days). When `long` is full: `./stack/up.sh -p short -c 16 --mem=100G -t 1-00:00:00`,
then queue the long job behind it with `--dependency=afterany:<short job id>`.

## Use

`./stack/qiita-dev.sh <args>` runs the `qiita` CLI on the stack's node with the master token, e.g.
`submit-ena-import PRJDB13464`, `reference list`, `ticket status <idx>`. Logs are in `$QDEV_ROOT/logs/`.
Import-pilot and read-processing scripts live in
[jbk708/qiita-cq-analysis](https://github.com/jbk708/qiita-cq-analysis).

## Share it with a colleague

The control plane and data plane listen on the node's address (Postgres and the orchestrator stay on localhost);
the stack writes the current URLs to `$QDEV_SHARE/stack.env` on every start. Give each person their own token:
`stack/add_user.py <name> <email> <user|wet_lab_admin|system_admin> <token_file>` (run on the stack's node with
`env/control-plane.env` loaded). They then use the `qiita` CLI with `QIITA_CONTROL_PLANE_URL` + `QIITA_TOKEN`, or the
web UI (`qiita-web`, `QIITA_BASE=<control plane URL> npm run dev`) with the token pasted in.

## Keep it up

`stack/watch-stack.sh` (detached on the login node) restarts the stack when a service dies or the control plane
stops answering: it stops Postgres cleanly, submits a replacement that waits for the old job, repoints any pending
stack job, and cancels the old one. At most 3 restarts per 24 h; log in `$QDEV_ROOT/logs/watch-stack.log`.

## Update the code

Check no ticket is running (`./stack/qiita-dev.sh ticket list`), then: update `$QDEV_ROOT/Qiita` (merge or pull, no commit
trailers), `./stack/build.sh`, `scancel` the stack job, `./stack/up.sh`. Each start runs `make migrate`
and `make sync-actions`, so new migrations and workflows land on restart.

## Gotchas

- Wrap `ssh`/`srun`/`curl` in `timeout`; barnacle Docker and the VPN stall.
- `srun --jobid … --overlap` needs `-n 1`, or one command runs once per allocated CPU.
- Compute nodes have no `g++`: the data plane builds in `rust_1.91.sif` with `--features duckdb/bundled`.
- Postgres in apptainer needs `shared_memory_type=sysv` (POSIX shm gives SIGBUS).
- Files given to the CLI (reference FASTAs, manifests) must sit under `$QDEV_ROOT/scratch` (the ingest root).
