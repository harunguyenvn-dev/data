#!/bin/bash

INPUT_FILE="link.txt"
OUTPUT_FILE="data.csv"
API_DOMAIN="https://api-zophim.blogspot.com"
PLAY_DOMAIN="https://ssplay.net/v"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

echo "name,episodes,link" > "$OUTPUT_FILE"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "❌ Hân không thấy file '$INPUT_FILE' đâu cả!"
    exit 1
fi

echo "🩹 Hân bắt đầu quá trình sửa lỗi và quét sâu..."

while IFS= read -r LIST_URL || [ -n "$LIST_URL" ]; do
    [[ -z "$LIST_URL" ]] && continue
    echo "🎯 Đang quét TRANG CHỦ: $LIST_URL"

    PAGE_CONTENT=$(curl -sL -A "$UA" "$LIST_URL" | tr '\n' ' ' | sed "s/&#39;/'/g")

    echo "$PAGE_CONTENT" | grep -oP "<tr onclick.*?</tr>" > raw_movies.tmp

    TOTAL_MOVIES_FOUND=$(wc -l < raw_movies.tmp)
    echo "    📦 Đã tìm thấy $TOTAL_MOVIES_FOUND hàng dữ liệu."

    while read -r MOVIE_BLOCK; do

        RAW_NAME=$(echo "$MOVIE_BLOCK" | grep -oP 'width="30%".*?<font.*?>\K.*?(?=</font>)' | sed 's/<[^>]*>//g') 
        
        RAW_SLUG=$(echo "$MOVIE_BLOCK" | grep -oP "onclick=\"window.location='\K.*?(?='\")")

        
        if [[ -z "$RAW_NAME" || -z "$RAW_SLUG" ]]; then

           continue
        fi

        DETAIL_FULL_LINK="${API_DOMAIN}${RAW_SLUG}"
        echo "       🎬 Tìm thấy phim: [ $RAW_NAME ] -> 🔍 Mò vào trang con..."

        DETAIL_HTML=$(curl -sL -A "$UA" "$DETAIL_FULL_LINK")


        DETAIL_FLAT=$(echo "$DETAIL_HTML" | tr '\n' ' ')
        

        DATA_AREA=$(echo "$DETAIL_FLAT" | grep -oP 'class="ALL">\K.*?(?=<\/td>)')

        IFS=$'\n' 
        
        
        DATA_LINES=$(echo "$DATA_AREA" | sed 's/<br[^>]*>/\n/g')

        for LINE in $DATA_LINES; do
            
            [[ -z "$LINE" ]] && continue
            
            
            if [[ "$LINE" != *"|"* ]]; then continue; fi

            
            COL1=$(echo "$LINE" | cut -d'|' -f2) 
            COL2=$(echo "$LINE" | cut -d'|' -f3) 

            
            EPISODE=$(echo "$LINE" | cut -d'|' -f1 | tr -d ' ')
            
            
            COL1_CLEAN=$(echo "$COL1" | tr -d ' ' | tr -d '-') 
            COL2_CLEAN=$(echo "$COL2" | tr -d ' ' | tr -d '-') 

            FINAL_URL=""

  
            if [[ -z "$COL2_CLEAN" ]]; then
  
                if [[ -n "$COL1_CLEAN" ]]; then
                    FINAL_URL="${PLAY_DOMAIN}/${COL1_CLEAN}.html"
                fi
            else
  
                FINAL_URL="${PLAY_DOMAIN}/${COL1_CLEAN}/${COL2_CLEAN}"
            fi

  
            if [[ -n "$FINAL_URL" ]]; then
  
                echo "\"$RAW_NAME\",\"$EPISODE\",\"$FINAL_URL\"" >> "$OUTPUT_FILE"

            fi
        done
        unset IFS Ấ

        echo "       ✅ Đã cất gọn vào kho. ($RAW_NAME)"

    done < raw_movies.tmp
    rm raw_movies.tmp

done < "$INPUT_FILE"

echo "✨----------------------------------------------✨"
echo " (ノ_<。)  HOÀN TẤT >____<
echo "✨----------------------------------------------✨"
