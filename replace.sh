#!/bin/bash

# 対象のディレクトリ
directory=$1
# 置換対象の文字列
search_string=$2
# 新しい文字列
replace_string=$3

# 対象ディレクトリ以下のファイルで文字列を置換
find "$directory" -type f -exec sed -i "s/$search_string/$replace_string/g" {} +
