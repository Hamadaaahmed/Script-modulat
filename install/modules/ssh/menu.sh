#!/usr/bin/env bash
set -euo pipefail

while true; do
  clear
  echo "============================================"
  echo "              HAMADA NET SSH"
  echo "============================================"
  echo "[1] Create SSH Account"
  echo "[2] Trial SSH Account"
  echo "[3] Renew SSH Account"
  echo "[4] Delete SSH Account"
  echo "[5] Check Active Logins"
  echo "[6] Show SSH Accounts"
  echo "[0] Back"
  echo "============================================"
  read -rp "Select Menu : " opt
  case "$opt" in
    1) add-ssh ;;
    2) trial-ssh ;;
    3) renew-ssh ;;
    4) del-ssh ;;
    5) cek-ssh ;;
    6) show-ssh ;;
    0) exit 0 ;;
    *) echo "Invalid option"; sleep 1 ;;
  esac
done
