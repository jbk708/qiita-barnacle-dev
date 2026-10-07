"""Add a person to the dev stack and mint their non-expiring token (no AuthRocket, so no other way to get one).
Usage: add_user.py <display_name> <email> <system_role> <token_out_path>   (system_role: user, wet_lab_admin, system_admin)
"""
import asyncio, os, sys
import asyncpg
from qiita_common.auth_constants import SYSTEM_PRINCIPAL_IDX, SystemRole
from qiita_control_plane.auth.scopes import ROLE_IMPLIED_SCOPES
from qiita_control_plane.auth.token import mint_api_token


async def main(name: str, email: str, role: str, out_path: str) -> None:
    role = SystemRole(role)
    pool = await asyncpg.create_pool(os.environ["DATABASE_URL"], min_size=1, max_size=2)
    async with pool.acquire() as conn, conn.transaction():
        idx = await conn.fetchval("SELECT idx FROM qiita.principal WHERE display_name = $1", name)
        if idx is None:
            idx = await conn.fetchval(
                "INSERT INTO qiita.principal (display_name, system_role, created_by_idx)"
                " VALUES ($1, $2, $3) RETURNING idx",
                name, role, SYSTEM_PRINCIPAL_IDX,
            )
            await conn.execute(
                "INSERT INTO qiita.user (principal_idx, email, affiliation, address, phone)"
                " VALUES ($1, $2, 'dev', 'dev', 'dev')",
                idx, email,
            )
    plaintext, _ = await mint_api_token(
        pool, principal_idx=idx, label=f"dev-{name}", scopes=list(ROLE_IMPLIED_SCOPES[role]),
    )
    await pool.close()
    fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(plaintext + "\n")
    print(f"{role.value} token for principal {idx} ({name}) written to {out_path}")


asyncio.run(main(*sys.argv[1:5]))
