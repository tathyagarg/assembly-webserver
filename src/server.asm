%include 'src/functions.asm'
%include 'src/sockets.asm'

section .data
    socket      dq      0
    socket_on   dq      1
    max_backlog dw      10

    buf_len     equ     512              ; Request buffer length, 512 bytes
    req_buf     TIMES   buf_len db 0     ; Request buffer
    res_buf     TIMES   buf_len db 0     ; Response buffer

    req_len     dq      0                ; Request length


    DEBUG       dq      1

    client      dq      0

    address     dq      0100007Fh        ; 127.0.0.1 in big endian hex
    port        dw      901Fh            ; 8080 in little endian hex

    startup_msg:
        db      "Server started and listening on http://127.0.0.1:8080", 0ah, 0ah, 0h
    startup_msg_len equ $ - startup_msg

    ; ============= Files =============
    html_file_ptr    dq      0
    css_file_ptr     dq      0

    index_html:
        db      "src/templates/home/index.html", 0h
    index_html_len equ $ - index_html

    style_css:
        db      "src/templates/home/style.css",  0h
    style_css_len equ $ - style_css

    ; ============= Responses =============
    html_http_200:
        db      "HTTP/1.1 200 OK",                 0dh, 0ah
        db      "Server: Tathya's Awesome Server", 0dh, 0ah
        db      "Content-Type: text/html",           0dh, 0ah
        db      0dh, 0ah
    html_http_200_len equ $ - html_http_200

    css_http_200:
        db      "HTTP/1.1 200 OK",                 0dh, 0ah
        db      "Server: Tathya's Awesome Server", 0dh, 0ah
        db      "Content-Type: text/css",           0dh, 0ah
        db      0dh, 0ah
    css_http_200_len equ $ - css_http_200

section .bss
    socket_addr resq    1  ; Declare 8 bytes of uninitialized memory

section .text
global _start

error_handler:
    cmp  rax, 0
    jne  _exit
    ret

jle_error_handler:
    cmp  rax, 0
    jle  _exit
    ret

; ============= Send File =============
; Sends a file to the client buffer
; Reads the file contents into res_buf and sends it to the client
; Loops until the file is completely read
;
; Parameters:
;   rbx: File pointer/descriptor (provided by caller)
send_file:
    ; Read the file contents
    mov  rdi, rbx
    mov  rsi, res_buf
    mov  rdx, buf_len
    call so_read_socket
    cmp  rax, 1                         ; Check if bytes read is < 1
    jl   finish_send_file
    mov  rcx, rax                       ; Store bytes read to counter

    ; Write the file contents to the client
    mov  rdi, [client]
    mov  rsi, res_buf
    mov  rdx, rcx
    call so_write_socket
    jmp  send_file

finish_send_file:
    ret

_start:
    call so_create_socket
    mov  [socket], rax                 ; Store socket file descriptor

    ; ========== Create Socket Address ==========
    ; The socket address structure is defined in netinet/in.h
    ; struct sockaddr_in {
    ;     sa_family_t    sin_family;  // Address Family
    ;     in_port_t      sin_port;    // Port Number
    ;     struct in_addr sin_addr;    // Internet Address
    ; };
    ;
    ; sin_family is the address family (AF_INET). Size: word (2 bytes)
    ; sin_port is the port number. Size: word (2 bytes)
    ; sin_addr is the internet address. Size: dword (4 bytes)
    ;
    ; When elements are pushed to the stack, rsp is decremented.
    ; This means to restore rsp to its original value, we need to add to it (not subtract!)
    ; 
    push rbp                             ; Store stack pointer (base)
    mov  rbp,  rsp                       ; Move stack top to base
    push qword [address]                 ; Push the address to the stack
    push word  [port]                    ; Push the port to the stack
    push word  2                         ; Push the address family (AF_INET) to the stack
    mov  [socket_addr], rsp              ; Store the address pointer
    add  rsp, 8                          ; Add to the stack pointer to restore its position 
    pop  rbp                             ; Restore original stack pointer

    mov  rdi, [socket]                   ; Load socket file descriptor
    mov  r10, socket_on                  ; Enable socket reuse
    call so_set_socket_options
    call error_handler

    ; Bind the socket to the address
    mov  rdi, [socket]
    mov  rsi, [socket_addr]
    call so_bind_socket
    call error_handler

    ; Print the startup message
    mov  rsi, startup_msg
    mov  rdx, startup_msg_len
    call print

    ; Listen for incoming connections
    mov  rdi, [socket]
    mov  rsi, [max_backlog]              ; Set the backlog to 10
    call so_listen

accept:
    ; Accept incoming connections
    mov  rdi, [socket]                   ; Load the socket file descriptor
    call so_accept_connection
    call jle_error_handler
    mov  [client], rax

    ; Read the request from the client
    mov  rdi, [client]
    mov  rsi, req_buf
    mov  rdx, buf_len 
    call so_read_socket
    mov  [req_len], rax

    ; Print the request headers, if DEBUG
    cmp  dword [DEBUG], 0
    je   process_request
    mov  rsi, req_buf
    mov  rdx, [req_len]
    call print

process_request:
    ; Open the index.html file, read it's contents, store them in html_file_ptr
    mov  rdi, index_html
    call so_open_file
    cmp  rax, 0
    jle  close_client
    mov  [html_file_ptr], rax

    ; mov  rdi, style_css
    ; call so_open_file
    ; cmp  rax, 0
    ; jle  close_client
    ; mov  [css_file_ptr], rax

    ; Reset the counter
    mov  rcx, qword 0

send_headers:
    ; Write the HTTP 200 OK headers
    mov  rdi, [client]
    mov  rsi, html_http_200
    mov  rdx, html_http_200_len
    call so_write_socket

    ; Send the index.html file
    mov  rbx, [html_file_ptr]
    call send_file

    ; mov  rdi, [client]
    ; mov  rsi, css_http_200
    ; mov  rdx, css_http_200_len
    ; call so_write_socket
    ; mov  rbx, [css_file_ptr]
    ; call send_file

close_client:
    ; Close the client connection
    mov  rdi, [client]
    call so_close_socket
    jmp  accept

_exit:
    mov  rdi, [socket]
    call so_close_socket
    call quit

