#!/usr/bin/python3
"""Run with desktop-agent Python, without an attached viewer."""
import json,os,subprocess,time
from pathlib import Path
import mss
import pyautogui
assert os.environ.get('DISPLAY')==':1'
assert tuple(pyautogui.size())==(1600,900)
assert subprocess.run(['/agentenv/deskd','check'],check=True).returncode==0
pyautogui.hotkey('ctrl','alt','t');time.sleep(1.5)
window=subprocess.check_output(['xdotool','getactivewindow'],text=True).strip()
assert 'xfce4-terminal' in subprocess.check_output(['xprop','-id',window,'WM_CLASS'],text=True).lower()
nonce='taskenv-'+str(time.time_ns())
command="printf '%s\\n' '"+nonce+"' > /home/ubuntu/Shared/taskenv-input.txt"
pyautogui.write(command,interval=.005);pyautogui.press('enter')
p=Path.home()/'Shared/taskenv-input.txt'
for _ in range(50):
 if p.exists() and p.read_text().strip()==nonce:break
 time.sleep(.1)
else:raise AssertionError('desktop keyboard input failed')
pyautogui.screenshot().save('/tmp/taskenv-pyautogui.png')
with mss.mss() as shot:shot.shot(output='/tmp/taskenv-mss.png')
print(json.dumps({'result':'TASKENV_UNATTENDED_DESKTOP_PASS','nonce':nonce,'size':list(pyautogui.size())}))
