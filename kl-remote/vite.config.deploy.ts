// Bake the environments from QIITA_CONFIG into a production build; upstream reads them only under `vite dev`.
import { readFileSync } from 'node:fs';
import { parse } from 'smol-toml';
import { defineConfig, type UserConfig } from 'vite';
import base from './vite.config';

const raw = parse(readFileSync(process.env.QIITA_CONFIG as string, 'utf8')) as {
  current?: string;
  env?: Record<string, { base_url: string }>;
};
const envs = Object.entries(raw.env ?? {}).map(([name, t]) => ({ name, origin: t.base_url.replace(/\/+$/, '') }));
const current = envs.some((e) => e.name === raw.current) ? raw.current : envs[0]?.name;

export default defineConfig(async (env) => {
  const c = (typeof base === 'function' ? await base(env) : base) as UserConfig;
  c.define = { ...c.define, __QIITA_DEV_ENVS__: JSON.stringify(envs), __QIITA_DEV_DEFAULT_ENV__: JSON.stringify(current) };
  return c;
});
