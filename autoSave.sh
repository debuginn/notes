echo "------ job start ------"
#!/bin/bash
cd /Users/mengxiaoyu/Documents/Notes
DIR=$(cd $(dirname $0) && pwd )
echo  $DIR
echo "- set local git config -"
git config --local user.name 'debuginn' && git config --local user.email 'debuginn@icloud.com'
echo "- git pull origin main -"
git pull origin main
echo "- git push origin main -"
git add .
git commit -m "crontab auto save"
git push -u origin main
echo "------ job end ------"
