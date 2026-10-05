"""Seed a system_admin principal and mint a non-expiring master PAT (dev stack only)."""
import asyncio, os, sys
import asyncpg
from qiita_common.auth_constants import SYSTEM_PRINCIPAL_IDX, SystemRole
from qiita_control_plane.auth.scopes import ROLE_IMPLIED_SCOPES
from qiita_control_plane.auth.token import mint_api_token

NAME = "dev-master-admin"

async def main(out_path: str) -> None:
    pool = await asyncpg.create_pool(os.environ["DATABASE_URL"], min_size=1, max_size=2)
    async with pool.acquire() as conn, conn.transaction():
        idx = await conn.fetchval("SELECT idx FROM qiita.principal WHERE display_name = $1", NAME)
        if idx is None:
            idx = await conn.fetchval(
                "INSERT INTO qiita.principal (display_name, system_role, created_by_idx)"
                " VALUES ($1, $2, $3) RETURNING idx",
                NAME, SystemRole.SYSTEM_ADMIN, SYSTEM_PRINCIPAL_IDX,
            )
            await conn.execute(
                "INSERT INTO qiita.user (principal_idx, email, affiliation, address, phone)"
                " VALUES ($1, $2, 'dev', 'dev', 'dev')",
                idx, os.environ["QDEV_EMAIL"],
            )
    plaintext, _ = await mint_api_token(
        pool, principal_idx=idx, label="dev-master",
        scopes=list(ROLE_IMPLIED_SCOPES[SystemRole.SYSTEM_ADMIN]),
    )
    await pool.close()
    fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(plaintext + "\n")
    print(f"master token for principal {idx} written to {out_path}")

asyncio.run(main(sys.argv[1]))
