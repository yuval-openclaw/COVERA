import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Lets phones on the local network load the dev server (e.g. http://192.168.3.115:3100).
  allowedDevOrigins: ['192.168.*.*', '10.*.*.*', '*.local'],
};

export default nextConfig;
