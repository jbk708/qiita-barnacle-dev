# qiita-barnacle-dev

A personal, throwaway [Qiita](https://github.com/the-miint/Qiita) stack on barnacle, plus read-processing
scripts that run outside Qiita. One Slurm job hosts Postgres (apptainer), the data plane, the control plane
and the compute orchestrator on localhost. Downloads run in-process (`COMPUTE_BACKEND=local`), auth is one
master admin token (AuthRocket off), and nothing migrates to production.

Settings live in [`config.sh`](config.sh): `QDEV_ROOT` (stack), `QDEV_SHARE` (shared reads), `QDEV_CONDA`,
`QDEV_ACCOUNT` (required), `QDEV_EMAIL`. Override them in the environment.

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

- CLI: `./stack/qiita-dev.sh <args>`, e.g. `submit-ena-import PRJDB13464`, `reference list`,
  `ticket submit --action-id amplicon …`. It runs `qiita` on the stack's node with the master token.
- Status: `./stack/watch.sh <batch_idx>`, `./stack/progress.sh`, logs in `$QDEV_ROOT/logs/`.
- Share imported reads with the group: `./stack/share-refresh.sh` after each wave (manifest, permissions,
  and a copy of `pipeline/` plus [`docs/reads-share.md`](docs/reads-share.md) into `$QDEV_SHARE`).

## Update the code

Check no ticket is running (`watch.sh`), then: update `$QDEV_ROOT/Qiita` (merge or pull, no commit
trailers), `./stack/build.sh`, `scancel` the stack job, `./stack/up.sh`. Each start runs `make migrate`
and `make sync-actions`, so new migrations and workflows land on restart.

## Pipelines (outside Qiita)

| Script | Does |
|---|---|
| `pipeline/submit_runs.sh <out> PRJ…` | Slurm array over a study's metagenomic runs → `deplete_sketch.sh` |
| `pipeline/deplete_sketch.sh` | parquet → miint FASTQ stream → deacon (panhuman-1) → sylph sketch |
| `pipeline/profile.sh <out>` | sylph profile vs GTDB r232, then sylph-tax |
| `pipeline/amplicon_check.py PRJ…` | per-study 16S region, primers, trim, multiplexing → `amplicon` args |
| `pipeline/jupyter.sbatch`, `qiita_reads.ipynb` | JupyterLab on the `jupyter` partition |

Databases (panhuman-1, GTDB r232 sylph db, sylph-tax) are expected in `$QDEV_SHARE/db/`; the conda env
(DuckDB 1.5.4, deacon, sylph, sylph-tax, JupyterLab) in `$QDEV_CONDA`.

## Gotchas

- Wrap `ssh`/`srun`/`curl` in `timeout`; barnacle Docker and the VPN stall.
- `srun --jobid … --overlap` needs `-n 1`, or one command runs once per allocated CPU.
- Compute nodes have no `g++`: the data plane builds in `rust_1.91.sif` with `--features duckdb/bundled`.
- Postgres in apptainer needs `shared_memory_type=sysv` (POSIX shm gives SIGBUS).
- DuckDB sizes itself to the node, not the Slurm allocation: always set `memory_limit`.
- Files given to the CLI (reference FASTAs, manifests) must sit under `$QDEV_ROOT/scratch` (the ingest root).
- No POSIX ACLs: sharing goes through the Unix group.
