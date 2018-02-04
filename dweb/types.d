module dweb.types;

struct Void
{
    @property static Void* nullptr() { return cast(Void*)null; }
}
