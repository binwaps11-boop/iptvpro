// Keep the pinned LuCI identity while changing the resource revision whenever
// Smart AP ships a frontend fix.  LuCI appends this value to JavaScript URLs,
// preventing browsers from retaining a known-broken view across sysupgrade.
export const revision = '26.181.75678~128a781-smartap-v86', branch = 'LuCI (HEAD detached at 128a7812) branch';
