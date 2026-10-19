#!/bin/zsh
# Claude SE D-day 바탕화면을 지금 바로 원래대로 되돌리고 예약을 지운다
osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$(cat ~/.wallpaper_backup.txt)\""
launchctl bootout gui/$(id -u)/com.claude.sewallpaper 2>/dev/null
rm -f ~/Library/LaunchAgents/com.claude.sewallpaper.plist
echo "원래 바탕화면으로 돌아왔어요."
