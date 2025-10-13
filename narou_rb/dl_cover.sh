#!/usr/bin/env bash
set -euxo pipefail

while true; do
    IFS=',' read -ra DL_COVER_LIST <<< "$DL_COVER_SITE"
    BASE_DIR="/share/data/小説データ"

    for site in "${DL_COVER_LIST[@]}"; do
        DIR="${BASE_DIR}/${site}"
        if [ -d "$DIR" ]; then
            echo "Found directory: $DIR"
            while IFS= read -r -d '' tocdir; do
                echo "Moving to: $tocdir"
                cd "$tocdir"
                if [ -f "toc.yaml" ]; then
                    toc_url=$(grep '^toc_url:' toc.yaml | head -n1 | sed 's/^toc_url:[[:space:]]*//')
                    if [ -n "$toc_url" ]; then
                        found=0
                        for ext in jpg png gif; do
                            # 既にcover画像が存在する場合はスキップ
                            if [ -f "cover.jpg" ] || [ -f "cover.png" ] || [ -f "cover.gif" ]; then
                                echo "Cover image already exists in $tocdir, skipping download."
                                found=1
                                break
                            fi
                            url="${toc_url%/}/cover.${ext}"
                            sleep 1
                            if wget --quiet --spider "$url"; then
                                wget -O "cover.${ext}" "$url"
                                echo "Downloaded: $url"
                                found=1
                                break
                            fi
                        done
                        if [ "$found" -eq 0 ]; then
                            echo "No cover image found for $toc_url"
                        fi
                    else
                        echo "toc_url not found in toc.yaml"
                    fi
                fi
                cd - >/dev/null
            done < <(find "$DIR" -type f -name "toc.yaml" -print0 | xargs -0 -n1 dirname | sort -u -z)
        else
            echo "Directory not found: $DIR"
        fi
    done
    echo "Waiting 2 hours before next run..."
    sleep 7200
done