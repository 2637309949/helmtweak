import sys, os
sys.path.insert(0, 'scripts')
from device import connect, run
c = connect()

print("=== find mcp prefs ===")
outs = []
outs.append(run(c, 'find /var/mobile/Library/Preferences -iname "*mcp*" 2>/dev/null'))
outs.append(run(c, 'find /var/root/Library/Preferences -iname "*mcp*" 2>/dev/null'))
outs.append(run(c, 'grep -arl "witchan.ios-mcp" /var/mobile/Library/Preferences /var/root/Library/Preferences 2>/dev/null'))
for rc, out, err in outs:
    print('rc=', rc, 'out=', out, 'err=', err)

print("=== ios-mcp plist content ===")
print(run(c, 'plutil -p /var/mobile/Library/Preferences/com.witchan.ios-mcp.preferences.plist 2>/dev/null'))
print(run(c, 'plutil -p /var/root/Library/Preferences/com.witchan.ios-mcp.preferences.plist 2>/dev/null'))