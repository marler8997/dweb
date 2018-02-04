
module dweb.httpserver;

import std.array : Appender;

import more.types : passfail, passed, failed;
import more.net : socket_t, socklen_t, lastError, isInvalid, htons,
                  inet_sockaddr, in_addr, accept, recv, send, shutdown, Shutdown, closesocket;
import more.httpparser : HttpParser, HttpBadRequestReason;

import dweb.types;
import dweb.log;
import dweb.server : HandlerResult;
import dweb.http : StopHttpParserException;


template HttpServer(alias ServerAlias)
{
    //static assert(Hooks.isGlobal, "non global not supported yet");
    HandlerResult globalServerListenCallback(ServerAlias.Event!Void event)
    {
        inet_sockaddr from;
        socklen_t fromlen = from.sizeof;

        auto newClient = accept(event.sock, &from);
        if(newClient.isInvalid)
        {
            errorf("accept(s=%s) failed (e=%s)", event.sock, lastError);
            return HandlerResult.errorStopServer;
        }
        logf("received new connection from %s", from);

        auto newClientData = HttpServerConnectionData();
        newClientData.parser.sock = newClient;
        if(failed(ServerAlias.addReadSocket!HttpServerConnectionData(newClient,
            &globalServerDataCallback, &newClientData)))
        {
            // error already logged
            shutdown(newClient, Shutdown.both);
            closesocket(newClient);
            return HandlerResult.errorStopServer;
        }
        return HandlerResult.success;
    }
    HandlerResult globalServerDataCallback(ServerAlias.Event!HttpServerConnectionData event)
    {
        char[1] buffer; // still works with 1-byte buffer, cool!!!!
        //char[500] buffer;


        auto length = recv(event.sock, buffer);
        if(length <= 0)
        {
            logf("dataCallback(s=%s) recv returned %s (e=%s)", event.sock, length, lastError);
            shutdown(event.sock, Shutdown.both);
            closesocket(event.sock);
            return HandlerResult.removeSocket;
        }
        //logf("dataCallback(s=%s) read %s bytes of data", event.sock, length);
        try
        {
            event.parser.parse(buffer[0..length]);
        }
        catch(StopHttpParserException e)
        {
            shutdown(event.sock, Shutdown.both);
            closesocket(event.sock);
            return HandlerResult.removeSocket;
        }
        if(event.parser.done)
        {
            sendResource(event.sock, event.parser.method, event.parser.uri);
            shutdown(event.sock, Shutdown.both);
            closesocket(event.sock);
            return HandlerResult.removeSocket;
        }

        return HandlerResult.success;
    }
}

struct ResponseBuilder
{
    char* next;
    char* limit;
    this(char[] buffer)
    {
        this.next = buffer.ptr;
        this.limit = buffer.ptr + buffer.length;
    }
    auto diff(char* from) const { return next - from; }
    void put(const(char)[] str)
    {
        auto newNext = next + str.length;
        if(newNext > limit)
        {
            assert(0, "not implemented");
        }
        else
        {
            next[0..str.length] = str[];
            next = newNext;
        }
    }
}
void sendResource(socket_t sock, HttpMethod method, string uri)
{
    char[100] response;
    uint responseLength;
    {
        auto builder = ResponseBuilder(response);
        builder.put("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: text/html\r\n\r\n");
        logf("URI is \"%s\"", uri);
        if(uri == "/")
        {
            logf("sending Hello!");
            builder.put("<h1>Hello!</h1>");
        }
        else
        {
            // do not send anything
            logf("sending blank response");
        }
        responseLength = cast(uint)builder.diff(response.ptr);
    }
    logf("sending \"%s\"", response[0..responseLength]);
    auto result = send(sock, response.ptr, responseLength);
    if(result != responseLength)
    {
        errorf("sendResponse(s=%s) send returned %s (e=%s)", sock, result, lastError);
    }
}

enum HttpMethod : ubyte
{
    GET,
}

struct HttpServerConnectionData
{
    HttpParser!HttpParserHooks parser;
}
private struct HttpParserHooks
{
    alias DataType = char;
    enum SupportPartialData = true;
    enum SupportCallbackStop = false;
    enum MaximumHeaderName = 200;
    enum MaximumMethodName = 100;
    mixin template HttpParserMixinTemplate()
    {
        import more.net : socket_t;
        import dweb.util : Partial;
        import dweb.httpserver : HttpMethod;
        // TODO: I could get the sock from the parser pointer
        socket_t sock;
        HttpMethod method;
        Partial partial;
        string uri;
    }
    static void onBadRequest(HttpParser!HttpParserHooks* parser, HttpBadRequestReason reason)
    {
        errorf("(s=%s) bad http request: %s", parser.sock, reason);
        throw new StopHttpParserException();
    }
    static void onMethodPartial(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        parser.partial.append(buffer);
    }
    static void onMethod(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        auto method = parser.partial.finish(buffer);
        if(method == "GET")
        {
            logf("(s=%s) Method=GET", parser.sock);
            parser.method = HttpMethod.GET;
        }
        else
        {
            errorf("(s=%s) unknown HTTP method \"%s\"", parser.sock, method);
            throw new StopHttpParserException();
        }
    }
    static void onUriPartial(HttpParser!HttpParserHooks* parser, char[] buffer)
    {   
        parser.partial.append(buffer);
    }
    static void onUri(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        // todo: since we are creating memory for the uri anyway,
        //       modify this to avoid extra allocation
        auto uri = parser.partial.finish(buffer);
        logf("(s=%s) Uri '%s'", parser.sock, uri);
        parser.uri = uri.dup;
    }
    static void onHeaderNamePartial(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        parser.partial.append(buffer);
    }
    static void onHeaderName(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        auto headerName = parser.partial.finish(buffer);
        logf("(s=%s) Header '%s'", parser.sock, headerName);
    }
    static void onHeaderValuePartial(HttpParser!HttpParserHooks* parser, const(char)[] buffer)
    {
        parser.partial.append(buffer);
    }
    static void onHeaderValue(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        auto headerValue = parser.partial.finish(buffer);
        logf("(s=%s) Value  '%s'", parser.sock, headerValue);
    }
    static void onHeadersDone(HttpParser!HttpParserHooks* parser, char[] buffer)
    {
        if(buffer.length > 0)
        {
            assert(0, "not implemented");
        }
    }
}
