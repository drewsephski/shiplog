import type { NextConfig } from 'next';
const config: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [{source: '/(.*)', headers: [
      // Preserve Origin on same-origin HTML form POSTs while withholding
      // referrers from GitHub and other external destinations.
      {key:'Referrer-Policy', value:'same-origin'},
      {key:'X-Content-Type-Options', value:'nosniff'},
      {key:'X-Frame-Options', value:'DENY'},
      {key:'Cache-Control', value:'no-store'},
    ]}];
  },
};
export default config;
