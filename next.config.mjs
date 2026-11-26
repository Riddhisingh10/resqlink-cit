/** @type {import('next').NextConfig} */
const portArgIdx = process.argv.findIndex(arg => arg === '-p' || arg === '--port');
const cliPort = portArgIdx !== -1 ? process.argv[portArgIdx + 1] : '';
const isPort3001 =
  process.env.PORT === '3001' ||
  cliPort === '3001' ||
  process.argv.some(arg => arg === '--port=3001');

const nextConfig = {
  distDir: process.env.NEXT_DIST_DIR || (isPort3001 ? '.next-3001' : '.next'),
};

export default nextConfig;
