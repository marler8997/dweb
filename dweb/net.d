module dweb.net;

import more.net :
    lastError, htons, isInvalid, invalidSocket, failed, socket_t, socklen_t,
    in_addr, inet_sockaddr, SocketType, Protocol, Shutdown,
    createsocket, closesocket, bind, listen, accept, shutdown, recv
    ;
import dweb.log;

// returns: invalid socket on error
socket_t createListenSocket(inet_sockaddr listenAddr)
{
    auto sock = createsocket(listenAddr.family, SocketType.stream, Protocol.tcp);
    if(sock.isInvalid)
    {
        errorf("socket function failed (e=%s)", lastError);
        return invalidSocket;
    }
    logf("created listen socket (s=%s)", sock);
    if(failed(bind(sock, &listenAddr)))
    {
        errorf("bind function failed (e=%s)", lastError);
        closesocket(sock);
        return invalidSocket;
    }
    if(failed(listen(sock, 128)))
    {
        errorf("listen function failed (e=%s)", lastError);
        closesocket(sock);
        return invalidSocket;
    }
    logf("listening at %s", listenAddr);
    return sock;
}