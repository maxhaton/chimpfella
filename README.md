# Easy Benchmarking for D (or any language D can call)
Use ranges to benchmark functions.

Give the library your function, a range, and some functions to generate test data and it handles the measurements for you.

As well as traditional functions, you can also benchmark the above against template parameters (i.e. is my code faster with 
a plain binary tree or a red black tree).

Currently only the Phobos Timer is supported but linux perf_event support is on the way.
Here's a snippet.


```D
static class StaticStore
    {

        import chimpfella.kernels;
        import chimpfella.measurement;
        import std.range : iota, repeat;
        import std.random : uniform;

        enum meas = [PhobosTimer("A stub").toMeasurement];

        @FunctionBenchmark!("Something with an integer", iota(1, 50), (x) => uniform(-x, x))(meas) 
        static void func(int l)
        {
            uint x;
            import core.volatile;

            foreach (_; 0 .. l)
                volatileStore(&x, _);
        }

        static auto getRandPair(T)(int x)
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
            return tmp;
        }

        @TemplateBenchmark!(0, int, float, double) 
        @FunctionBenchmark!("Templated add benchmark", 0.repeat(100), ForwardTemplate!(getRandPair))(meas) 
        static T templatedAdd(T)(T x, T y)
        {
            return x + y;
        }
        import std.algorithm;
        import std.array;
        static string ctfeRepeater(int n)
        {
            return "cpuid;".repeat(n).join();
        }
        
        enum cpuidRange = iota(1, 10).map!(ctfeRepeater).array;
        @TemplateBenchmark!(0, cpuidRange) 
        @FunctionBenchmark!("Measure", iota(1, 10), (_) => [1, 2, 3, 4])(meas) 
        static int sum(string asmLine)(inout int[] input)
        {
            //This is quite fun because ldc will sometimes get rid of the entire function body and just loop over the asm's
            int tmp;
            foreach (i; input)
            {
                mixin("asm { ", asmLine, ";}");
            }
            return tmp;
        }

        alias summat = sum!"mfence";
    }

    @safe struct PrintData
    {
        import chimpfella.measurement;

        auto getOutputHandle(string benchmarkName, scope const Measurements[] counters)
        {
            struct outputVoldy
            {
                string name;
                size_t width;
                import std;

                //You don't have to do anything with the header
                this(string setName, scope const Measurements[] them)
                {
                    name = setName;
                    writefln!"---------------%s---------------"(setName);
                    auto counterPut = counters.map!(x => x.getHeader);
                    //pragma(msg, ElementType!(typeof(counterPut)));
                    writeln("I;", counterPut.joiner!(typeof(counterPut)).joiner.joiner(";"));
                }

                void put(scope size_t[] data)
                {
                    data.map!(s => s.to!string).joiner(";").writeln;
                }

            }

            return outputVoldy(benchmarkName, counters);
        }
    }

    PrintData outBuf;
    auto dataOutput = MetaExecution!PrintData(outBuf);
    ExecuteBenchmarks!(StaticStore).run(dataOutput);
}
```
Produces (redacted) output 
```
---------------Something with an integer---------------
I;PhobosTimer
1;700
2;200
3;200
4;300
5;400
6;300
7;300
8;500
9;300
...
---------------Templated add benchmarkint---------------
I;PhobosTimer
0;700
0;200
0;400
...
---------------Templated add benchmarkfloat---------------
I;PhobosTimer
0;900
0;500
0;300
0;300
...
---------------Templated add benchmarkdouble---------------
I;PhobosTimer
0;600
0;300
0;200
0;200
0;300
...
---------------Measurecpuid;---------------
I;PhobosTimer
1;2500
2;2100
3;1800
4;1900
5;1900
6;2000
7;1900
8;1900
9;2000
---------------Measurecpuid;cpuid;---------------
I;PhobosTimer
1;7000
2;6600
3;6500
4;6500
5;6600
6;6600
7;26500
8;6400
9;6500
---------------Measurecpuid;cpuid;cpuid;---------------
I;PhobosTimer
1;11800
2;11200
3;11100
4;11200
5;11300
6;11100
7;11100
8;11300
9;11200
---------------Measurecpuid;cpuid;cpuid;cpuid;---------------
I;PhobosTimer
1;17900
2;16500
3;15700
4;15700
5;15700
6;15800
7;15700
8;15800
9;15800
---------------Measurecpuid;cpuid;cpuid;cpuid;cpuid;---------------
I;PhobosTimer
1;21200
2;20400
3;20400
4;20200
5;20700
6;20400
7;20400
8;20200
9;20200
---------------Measurecpuid;cpuid;cpuid;cpuid;cpuid;cpuid;---------------
I;PhobosTimer
1;25700
2;24900
3;25300
4;25100
5;24900
6;25200
7;25200
8;24800
9;25000
---------------Measurecpuid;cpuid;cpuid;cpuid;cpuid;cpuid;cpuid;---------------
I;PhobosTimer
1;30400
2;29400
3;29100
4;29500
5;29500
6;29400
7;29500
8;29500
9;29700
---------------Measurecpuid;cpuid;cpuid;cpuid;cpuid;cpuid;cpuid;cpuid;---------------
I;PhobosTimer
1;34800
2;34900
3;34300
4;34500
5;35100
6;34500
7;34500
8;34500
9;34300
---------------Measurecpuid;cpuid;cpuid;cpuid;cpuid;cpuid;cpuid;cpuid;cpuid;---------------
I;PhobosTimer
1;39500
2;39000
3;39600
4;38900
5;39200
6;39000
7;38900
8;39200
9;39100
---------------Measure---------------
I;PhobosTimer
1;1600
2;1100
3;800
4;800
5;800
6;900
7;1000
8;900
9;900
```