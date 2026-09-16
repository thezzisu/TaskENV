#!/usr/bin/python3
import json,subprocess,time
from pathlib import Path
import mss,pyautogui
pyautogui.hotkey('ctrl','alt','t');time.sleep(1.5)
pyautogui.write('/snap/bin/chromium --no-first-run http://localhost:3000',interval=.01)
pyautogui.press('enter')
for _ in range(120):
 r=subprocess.run(['xdotool','search','--onlyvisible','--name','TaskENV web test'],capture_output=True,text=True)
 if r.returncode==0:break
 time.sleep(.25)
else:raise AssertionError('Chromium did not open the web app')
window=r.stdout.splitlines()[0]
subprocess.run(['xdotool','windowactivate','--sync',window],check=True)
time.sleep(.5)
with mss.mss() as capture:capture.shot(output='/tmp/taskenv-browser.png')
print(json.dumps({'result':'TASKENV_CHROMIUM_UNATTENDED_PASS','window':window}))
