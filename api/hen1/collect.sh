#!/bin/bash


RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m' 

OUTPUT_FILE="link.txt"

> "$OUTPUT_FILE"

echo -e "${CYAN}🌸 ┌──────────────────────────────────────────────┐ ${RESET}"
echo -e "${CYAN}🌸 │     TOOLS - DATA COLLECTOR JOURNEY │ ${RESET}"
echo -e "${CYAN}🌸 └──────────────────────────────────────────────┘ ${RESET}"
echo ""

echo -e "${YELLOW}✏️  Bạn muốn thu thập dữ liệu trong bao nhiêu trang?${RESET}"
read -p ">> Nhập số lượng trang (ví dụ: 5): " TOTAL_PAGES


if ! [[ "$TOTAL_PAGES" =~ ^[0-9]+$ ]] || [ "$TOTAL_PAGES" -lt 1 ]; then
    echo -e "${RED}🥀 Nhập sai mất rồi! Phải là con số lớn hơn 0 ${RESET}"
    exit 1
fi

echo -e "\n${GREEN}🚀 Đang tiến hành thu thập data...${RESET}\n"


count_total_links=0

for ((i=1; i<=TOTAL_PAGES; i++)); do
    
    if [ $i -eq 1 ]; then
        URL="https://hentaiz.com.co/"
    else
        URL="https://hentaiz.com.co/page/${i}/"
    fi

    echo -ne "${CYAN}✨ Đang 'trích xuất cảm hứng' tại Trang $i...${RESET}\r"
    
  
    LINKS=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0 Safari/537.36" "$URL" | \
            grep 'class="video"' | \
            grep -o 'href="[^"]*"' | \
            sed 's/href="//g;s/"//g')

  
    if [ -n "$LINKS" ]; then
        echo "$LINKS" >> "$OUTPUT_FILE"
        count_page_links=$(echo "$LINKS" | wc -l)
        count_total_links=$((count_total_links + count_page_links))
        echo -e "${GREEN}✔ Hoàn tất trang $i: đã tìm thấy $count_page_links video mật :____0 💎${RESET}"
    else
        echo -e "${RED}✘ không tìm thấy gì ở trang $i ${RESET}"
    fi

    sleep 1
done


echo ""
echo -e "${CYAN}☁️ ┌───────────────────────────────────────────┐${RESET}"
echo -e "${CYAN}☁️ │ 🏆  THU THẬP HOÀN TẤT - MISSION COMPLETE! │${RESET}"
echo -e "${CYAN}☁️ └───────────────────────────────────────────┘${RESET}"
echo -e "${YELLOW}📝 Tổng kết: Đã lưu ${RED}${count_total_links}${YELLOW} đường link vào nhật ký '${OUTPUT_FILE}'${RESET}"
