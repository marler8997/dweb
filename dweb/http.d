module dweb.http;

// Used to stop the http parser
class StopHttpParserException : Exception
{
    this() { super(null); }
}