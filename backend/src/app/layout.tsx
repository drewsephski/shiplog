import type { Metadata } from 'next';
export const metadata: Metadata = {title:'Shiplog Agent',description:'An evidence-backed journal for the things you build.'};
export default function Layout({children}:{children:React.ReactNode}) { return <html lang="en"><body style={{fontFamily:'system-ui',maxWidth:560,margin:'12vh auto',padding:24}}>{children}</body></html>; }
