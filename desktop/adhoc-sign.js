// Without an Apple developer certificate the Mac app is "ad-hoc" signed, so Apple Silicon Macs can run it
// (an unsigned app would be reported as "damaged"). People still confirm the first launch once.
const { execFileSync } = require('child_process');
const path = require('path');

exports.default = async context => {
  if (context.electronPlatformName !== 'darwin') return;
  const appPath = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`);
  execFileSync('codesign', ['--force', '--deep', '--sign', '-', appPath], { stdio: 'inherit' });
};
