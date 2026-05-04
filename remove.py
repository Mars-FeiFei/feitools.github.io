"""
通用注释删除工具
不对文件类型做判断，对所有文件都应用所有语言的注释删除规则：
- C#:
- HTML:  跨行注释
- JavaScript:
- CSS: ，保留字符串内注�?

适用于任何文本文件，会删除所有匹配的注释模式
"""

import re
from pathlib import Path

def remove_all_comments(content):
    """
    删除文件中的所有注释（应用所有语言的注释规则）
    包括�?
    1. HTML 注释 
    2. C#/JS/CSS 多行注释 
    3. C#/JS 单行注释
    4. 保护字符串内容（引号内的内容�?
    5. 保护 JS 正则表达�?/.../
    6. 保护 C# 逐字字符�?@"..."
    7. 保护字符字面�?'...'
    """
    def in_string_state(in_double_quote_string, in_single_quote_string, 
                       in_backtick_string, in_char_literal):
        return in_double_quote_string or in_single_quote_string or in_backtick_string or in_char_literal
    
    lines = content.split('\n')
    result_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        new_chars = []
        j = 0
        length = len(line)
        in_multiline_comment = False
        in_html_comment = False
        in_line_comment = False
        in_single_quote_string = False
        in_double_quote_string = False
        in_backtick_string = False
        in_verbatim_string = False
        in_regex = False
        in_char_literal = False
        regex_buffer = []
        
        while j < length:
            if in_multiline_comment:
                if j + 1 < length and line[j] == '*' and line[j+1] == '/':
                    in_multiline_comment = False
                    j += 2
                else:
                    j += 1
                continue
            if in_html_comment:
                if j + 3 < length and line[j] == '-' and line[j+1] == '-' and line[j+2] == '>':
                    in_html_comment = False
                    j += 3
                else:
                    j += 1
                continue
            if in_line_comment:
                break
            if not in_string_state(in_double_quote_string, in_single_quote_string, 
                                  in_backtick_string, in_char_literal) and not in_regex:
                if j + 1 < length and line[j] == '@' and line[j+1] == '"':
                    in_verbatim_string = True
                    in_double_quote_string = True
                    new_chars.append(line[j])
                    new_chars.append(line[j+1])
                    j += 2
                    continue
            if not any([in_double_quote_string, in_single_quote_string, in_backtick_string, 
                       in_regex, in_char_literal, in_multiline_comment, in_html_comment]):
                if line[j] == '"':
                    in_double_quote_string = True
                    new_chars.append(line[j])
                    j += 1
                    continue
            if not any([in_double_quote_string, in_single_quote_string, in_backtick_string,
                       in_regex, in_multiline_comment, in_html_comment]):
                if line[j] == "'":
                    in_single_quote_string = True
                    new_chars.append(line[j])
                    j += 1
                    continue
            if not any([in_double_quote_string, in_single_quote_string, in_backtick_string,
                       in_regex, in_multiline_comment, in_html_comment]):
                if line[j] == '`':
                    in_backtick_string = True
                    new_chars.append(line[j])
                    j += 1
                    continue
            if not any([in_double_quote_string, in_single_quote_string, in_backtick_string,
                       in_regex, in_multiline_comment, in_html_comment]):
                if j + 2 < length and line[j] == "'" and line[j+2] == "'":
                    in_char_literal = True
                    new_chars.append(line[j])
                    j += 1
                    continue
            if in_double_quote_string:
                new_chars.append(line[j])
                if in_verbatim_string:
                    if j + 1 < length and line[j] == '"' and line[j+1] == '"':
                        new_chars.append(line[j+1])
                        j += 2
                        continue
                    elif line[j] == '"':
                        in_double_quote_string = False
                        in_verbatim_string = False
                else:
                    if line[j] == '\\' and j + 1 < length:
                        new_chars.append(line[j+1])
                        j += 2
                        continue
                    elif line[j] == '"':
                        in_double_quote_string = False
                j += 1
                continue
            
            if in_single_quote_string:
                new_chars.append(line[j])
                if line[j] == '\\' and j + 1 < length:
                    new_chars.append(line[j+1])
                    j += 2
                    continue
                elif line[j] == "'":
                    in_single_quote_string = False
                j += 1
                continue
            
            if in_backtick_string:
                new_chars.append(line[j])
                if line[j] == '\\' and j + 1 < length:
                    new_chars.append(line[j+1])
                    j += 2
                    continue
                elif line[j] == '`':
                    in_backtick_string = False
                j += 1
                continue
            
            if in_char_literal:
                new_chars.append(line[j])
                if line[j] == '\\' and j + 1 < length:
                    new_chars.append(line[j+1])
                    j += 2
                    continue
                elif line[j] == "'" and j > 0 and line[j-1] != '\\':
                    in_char_literal = False
                j += 1
                continue
            if not in_regex and not in_string_state(in_double_quote_string, in_single_quote_string, 
                                                   in_backtick_string, in_char_literal) and not in_multiline_comment and not in_html_comment:
                if line[j] == '/':
                    prev_char = ''
                    for k in range(len(new_chars) - 1, -1, -1):
                        if new_chars[k] not in (' ', '\t'):
                            prev_char = new_chars[k]
                            break
                    if prev_char in ('', '=', '(', '[', '{', ':', '!', '&', '|', '?', 
                                    ',', ';', '+', '-', '*', '/', '%', '<', '>', '^', '~',
                                    'return', 'if', 'for', 'while', 'switch', 'typeof',
                                    'instanceof', 'throw', 'case', 'delete', 'void'):
                        in_regex = True
                        regex_buffer = []
                        regex_buffer.append(line[j])
                        j += 1
                        continue
            if in_regex:
                regex_buffer.append(line[j])
                if line[j] == '\\' and j + 1 < length:
                    regex_buffer.append(line[j+1])
                    j += 2
                    continue
                if line[j] == '/':
                    new_chars.extend(regex_buffer)
                    in_regex = False
                j += 1
                continue
  - 多行注释: 
  - 单行注释:
  
保护内容:
  - 字符�? "..." '...' `...` (模板字符�?
  - C# 逐字字符�? @"..."
  - C# 字符字面�? 'a'
  - JS 正则表达�? /.../

示例:
  python remove_comments.py ./src
  python remove_comments.py ./src --dry-run
  python remove_comments.py ./src --backup
  python remove_comments.py ./src --ext .cs .js
  python remove_comments.py ./src --no-recursive
        '''
    )
    
    parser.add_argument('directory', help='要处理的根目录路�?)
    parser.add_argument('--ext', nargs='+', 
                       help='要处理的扩展名列表（�?.cs .js .txt），默认处理所有文本文�?)
    parser.add_argument('--backup', action='store_true', 
                       help='修改前备份原文件（保存为 .bak�?)
    parser.add_argument('--dry-run', action='store_true', 
                       help='仅预览文件，不实际修�?)
    parser.add_argument('--no-recursive', action='store_true', 
                       help='不递归子目录，仅处理当前目�?)
    
    args = parser.parse_args()
    
    list_and_process_files(
        root_dir=args.directory,
        extensions=args.ext,
        backup=args.backup,
        dry_run=args.dry_run,
        recursive=not args.no_recursive
    )

if __name__ == '__main__':
    main()