#!/bin/bash
cd /Users/mengxiaoyu/Documents/Notes
git config --local user.name 'debuginn' && git config --global user.email 'debuginn@icloud.com'
git add .
git commit -m "crontab auto save"
git push -u origin main
