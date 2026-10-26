#pragma once
// 요청 첫 줄(메서드·경로·쿼리)만 보는 작은 HTTP 서버. 인증이 없으니 LAN 에서만 쓴다.
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <thread>

struct HttpRequest {
    std::string method, path, query;   // query 는 '?' 뒤 그대로
};

class HttpServer {
public:
    using Handler = std::function<void(int fd, const HttpRequest&)>;
    std::atomic<bool> running{false};   // MJPEG 같은 긴 핸들러가 이 값을 보고 끝낸다

    HttpServer(std::string bindAddr, int port, Handler h) : addr(std::move(bindAddr)), port(port), handler(std::move(h)) {}
    ~HttpServer() { stop(); }

    bool start() {
        listenFd = socket(AF_INET, SOCK_STREAM, 0);
        if (listenFd < 0) return false;
        int one = 1;
        setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
        sockaddr_in a{};
        a.sin_family = AF_INET;
        a.sin_port = htons(port);
        if (inet_pton(AF_INET, addr.c_str(), &a.sin_addr) != 1 ||
            ::bind(listenFd, (sockaddr*)&a, sizeof a) != 0 || listen(listenFd, 8) != 0) {
            std::fprintf(stderr, "[http] %s:%d 열기 실패: %s\n", addr.c_str(), port, std::strerror(errno));
            close(listenFd);
            listenFd = -1;
            return false;
        }
        running = true;
        acceptor = std::thread([this] { acceptLoop(); });
        return true;
    }

    void stop() {
        if (!running.exchange(false)) return;
        if (acceptor.joinable()) acceptor.join();
        close(listenFd);
        for (int i = 0; i < 40 && active > 0; ++i) usleep(50000);   // 최대 2초
    }

    static bool writeAll(int fd, const char* p, size_t n) {
        while (n > 0) {
            ssize_t w = ::send(fd, p, n, MSG_NOSIGNAL);
            if (w <= 0) return false;
            p += w;
            n -= w;
        }
        return true;
    }

    static void respond(int fd, int code, const std::string& type, const std::string& body, const std::string& extra = "") {
        const char* text = code == 200 ? "OK" : code == 202 ? "Accepted" : code == 400 ? "Bad Request" : code == 404 ? "Not Found" : code == 405 ? "Method Not Allowed" : "Error";
        std::string h = "HTTP/1.1 " + std::to_string(code) + " " + text + "\r\nContent-Type: " + type +
                        "\r\nContent-Length: " + std::to_string(body.size()) + "\r\nCache-Control: no-store\r\nConnection: close\r\n" + extra + "\r\n";
        if (writeAll(fd, h.data(), h.size())) writeAll(fd, body.data(), body.size());
    }

private:
    void acceptLoop() {
        while (running) {
            pollfd p{listenFd, POLLIN, 0};
            if (poll(&p, 1, 500) <= 0) continue;
            int fd = accept(listenFd, nullptr, nullptr);
            if (fd < 0) continue;
            if (active >= 8) { close(fd); continue; }
            timeval tv{3, 0};
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
            ++active;
            std::thread([this, fd] { serve(fd); close(fd); --active; }).detach();
        }
    }

    void serve(int fd) {
        char buf[8192];
        size_t got = 0;
        while (got < sizeof buf - 1) {
            ssize_t r = recv(fd, buf + got, sizeof buf - 1 - got, 0);
            if (r <= 0) return;
            got += r;
            buf[got] = 0;
            if (std::strstr(buf, "\r\n\r\n")) break;
        }
        char method[8] = {0}, target[2048] = {0};
        if (std::sscanf(buf, "%7s %2047s", method, target) != 2) return;
        HttpRequest req;
        req.method = method;
        std::string t = target;
        auto q = t.find('?');
        req.path = t.substr(0, q);
        if (q != std::string::npos) req.query = t.substr(q + 1);
        handler(fd, req);
    }

    std::string addr;
    int port;
    Handler handler;
    int listenFd = -1;
    std::thread acceptor;
    std::atomic<int> active{0};
};
