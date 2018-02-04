module dweb.log;

import std.stdio : write, writefln;

alias logf = writefln;
void errorf(T...)(string fmt, T args)
{
    write("Error: ");
    writefln(fmt, args);
}
