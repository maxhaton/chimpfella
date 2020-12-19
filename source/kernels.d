module chimpfella.kernels;
import chimpfella.measurement;
import std.traits;
import std.range.primitives;

@nogc:
@safe:
/+++
If you want to generate templated data for a `TemplateBenchmark`, this will forward the current iterated
parameter to the parameter of ForwardTemplate.
+/
struct ForwardTemplate(alias forwardThis)
{
    alias contents = forwardThis;
}

///
struct FunctionBenchmark(string name, alias genIndependantVariable, alias independantToData = void)
        if (!is(genIndependantVariable == void) && isValidIndependantRange!genIndependantVariable)
{
    static if (!is(independantToData == void))
    {
        static if (isInstanceOf!(ForwardTemplate, independantToData))
        {
            //Forward template to it
            enum forward = true;
            //pragma(msg, "wowo");
        }
        else
        {
            enum forward = false;
            //Try to check some things early.
            static if (isCallable!(genIndependantVariable))
                alias elemT = ElementType!(typeof(genIndependantVariable()));
            else
                alias elemT = ElementType!(typeof(genIndependantVariable));
            alias forceEval = elemT;
            static if (__traits(isTemplate, independantToData))
                alias finalFunc = independantToData!forceEval;
            else
                alias finalFunc = independantToData;

            static if (arity!finalFunc)
            {
                enum compiles = __traits(compiles, finalFunc(elemT.init));
                //pragma(msg, fullyQualifiedName!finalFunc);
                static if (__traits(isTemplate, finalFunc))
                {
                    //pragma(msg, "Magic");
                }
                else
                {
                    static assert(__traits(compiles, finalFunc(elemT.init)));
                }

            }
        }

    }

    //The library knows everything about a function so running it with external data can be handled someplace else

    ///Template parameter repeated as a struct field to simplify code elsewhere.
    immutable string benchmarkName = name;

    alias genIndSet = genIndependantVariable;

    alias genData = independantToData;

    ///
    const Measurements[] measurementList;
    this(in Measurements[] theList)
    {
        measurementList = theList;
    }
}
///
enum isValidIndependantRange(alias T) = isInputRange!(typeof(T))
    || isInputRange!(ReturnType!(typeof(T)));
///
@safe unittest
{
    import std.range : iota;

    enum meas = [PhobosTimer("A stub").toMeasurement];
    @FunctionBenchmark!("Something with an integer", iota(1, 10_000))(meas) void func(int l)
    {

    }

    alias getIota = () => iota(1, 200);
    @FunctionBenchmark!("Something with an integer", getIota)(meas) void func2(int l)
    {

    }
}
///
struct TemplateBenchmark(uint pIndex, Args...)
{
    uint paramIndex = pIndex;
    alias paramPack = Args;
}
///
@safe unittest
{
    import std.meta;
    import std.range : repeat;

    auto getRandPair(T)()
    {
        import std.random;

        struct rndParams
        {
            AliasSeq!(T, T) pack;
        }

        rndParams tmp;
        auto rnd = Random(unpredictableSeed);

        // Generate an integer in [0, 1023]
        tmp.pack[0] = cast(T) uniform(0, 1024, rnd);
        tmp.pack[1] = cast(T) uniform(0, 1024, rnd);
    }

    @FunctionBenchmark!("int add benchmark", 0.repeat(100), getRandPair!int) int add(int x, int y)
    {
        return x + y;
    }

    @TemplateBenchmark!(0, int, float, double) @FunctionBenchmark!(
            "Templated add benchmark", 0.repeat(100), getRandPair) T templatedAdd(T)(T x, T y)
    {
        return x + y;
    }
}
