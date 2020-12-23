module chimpfella.execute;
import kernels;
import std.meta;

///Information from you about what to do with your benchmarks, where to put them, and what to do in between them.
public struct MetaExecution(ProcessBench)
{
    ///Output range to deal with the data generated (i.e. store in a file, dump to stdout etc.)
    ProcessBench storeData;
    this(ProcessBench sendSet)
    {
        storeData = sendSet;
    }
    //The output range is generic, so it can be from you but could also be dispatched at runtime via an interface
    ///What to do with the GC
    struct GCActions
    {

    }
    //
}

/+++
    Execution Engine:
    Takes multiple functions to be executed, however, they should be considered as a group, use multiple engines 
    for totally distinct functions.
+/
private template DefaultExecutionEngine(string fullName, FuncPack...)
        if (FuncPack.length > 0)
{
    alias theFunc = FuncPack[0];
    import chimpfella.measurement;

    void runEngine(MetaT, alias genInd, alias indToData)(
            scope ref MetaT metaExecutionState, const Measurements[] runThese)
    {
        import std.traits : isCallable;

        //start at one so we can store the independant variable
        size_t width = 1;
        foreach (meas; runThese)
        {
            width += procMeas!(m => m.eventCount())(meas);
        }
        size_t[] resultBuffer;
        {
            import core.stdc.stdlib : alloca;

            void* x = alloca(width * size_t.sizeof);
            resultBuffer = (cast(size_t*) x)[0 .. width];
            resultBuffer[] = 0;
        }
        static if (isCallable!genInd)
            auto indData = genInd();
        else
            auto indData = genInd;

        auto outputDataHere = metaExecutionState.storeData.getOutputHandle(fullName, runThese);
        foreach (indItem; indData)
        {
            resultBuffer[0] = indItem;
            //If generator function is void, give the independant variable straight to the function
            static if (is(indToData == void))
                const theData = indItem;
            else
                const theData = indToData(indItem);
            //Iterate over each measurement, but we don't yet consider the cost of each one.
            foreach (i, counter; runThese)
            {
                const measurementWidth = procMeas!(m => m.eventCount())(counter);
                //How many results have been given so far
                size_t countsRetired = 0;
                scope (exit)
                    countsRetired += measurementWidth;
                import std.traits : ReturnType;

                StateTypes state = counter.getState;
                procState!((ref x) => x.start)(state);
                //Hot stuff starts here
                static if (__traits(isSame, ReturnType!theFunc, void))
                {
                    //throw away, nothing we can do
                    theFunc(theData);
                    //Hot region ends
                    procState!((ref x) => x.stop)(state);
                }
                else
                {
                    import std.traits : arity, hasMember;

                    static if (arity!theFunc > 1)
                    {

                        static assert(hasMember!(typeof(theData), "pack"),
                                "Since D does not have multiple return values this library requires that you return some\n
                        type containing 
                        an AliasSeq of values named \"pack\" which the library will expand for you");
                        const res = theFunc(theData.pack);
                    }
                    else
                    {
                        const res = theFunc(theData);
                    }

                    //Hot region ends
                    procState!((ref x) => x.stop)(state);
                    //force a data dependancy on the output to trick the compiler
                    import core.volatile;

                    ubyte[res.sizeof] outputVolatile;
                    ubyte[] slicedInput = (cast(ubyte*)&res)[0 .. res.sizeof];
                    foreach (__i, ref d; slicedInput)
                    {
                        volatileStore(&outputVolatile[__i], d);
                    }
                }

                //We have the data, do something with it.
                {
                    import std.array : RefAppender, appender;

                    const startIdx = 1 + countsRetired;
                    auto app = resultBuffer[startIdx .. startIdx + measurementWidth];

                    procState!((ref x) => x.read(app))(state);
                }

                outputDataHere.put(resultBuffer);
            }

        }
    }

}
///Execute benchmarks from `fromHere` - i.e. this runs ExecutionEngine for you all those Benchmarks
template ExecuteBenchmarks(alias fromHere)
{
    import std.traits;
    import std.range : ElementType;

    void run(MetaT)(scope ref MetaT metaExecutionState)
    {
        alias udaList = getSymbolsByUDA!(fromHere, FunctionBenchmark);
        //Dispatch based on what other Benchmark UDAs we find.
        foreach (symbol; udaList)
        {
            //Symbol has a FunctionBenchmark
            alias funcBenchPack = getUDAs!(symbol, FunctionBenchmark);
            //If there is anything other than one the benchmarkark is ill formed
            static assert(funcBenchPack.length == 1);
            enum theFunctionBench = funcBenchPack[0];
            //Is it a template?
            static if (__traits(isTemplate, symbol))
            {
                //Should have a TemplateBenchmark attached to it to tell us what metaparameters to use.

                //Data generator is a template; We must instantiate it.
                enum generatorIsATemplate = __traits(isTemplate, theFunctionBench.genData);

                alias templateMetaPack = getUDAs!(symbol, TemplateBenchmark);
                const uint paramCov = templateMetaPack.length;
                //We need at least one
                static assert(paramCov, "there is a function benchmark attached to a symbol that is a template - it does not have a TemplateBenchmark");
                enum order(alias left, alias right) = left.index < right.index;
                //Get 'em in the right order

                alias sortedMetaPack = staticSort!(order, templateMetaPack);
                //Doesn't do every permutation (yet)
                foreach (packIdx, packItem; sortedMetaPack)
                {
                    //Process a single parameter
                    foreach (innerIdx, paramItem; packItem.paramPack)
                    {
                        import std.range.primitives;

                        //pragma(msg, "\t", paramItem);
                        //Work out what we're doing, then instantiate theFunc with it.
                        //Is it a type 
                        
                        //Parameter is fits the slot
                        static if (__traits(compiles, symbol!paramItem))
                        {
                            alias func = symbol!paramItem;

                            auto bench = theFunctionBench;
                            //static assert(!is(ReturnType!symbol == void), "benchmarked function may not (yet) be void. Support for ref args coming soon");
                            //Run the benchmark
                            alias engine = DefaultExecutionEngine!(theFunctionBench.benchmarkName ~ paramItem.stringof,
                                    func);
                            enum forwardTemplateParam = bench.forward;
                            alias genInd = bench.genIndSet;
                            alias genData_ = bench.genData;
                            alias IndT = ElementType!(typeof(genInd));

                            static if (__traits(isTemplate, genData_))
                            {
                                static assert(__traits(compiles, genData_!IndT));
                                alias genFunc = genData_!IndT;
                            }
                            else
                            {
                                static if (forwardTemplateParam)
                                {
                                    alias genFunc = genData_.contents!paramItem;
                                }
                                else
                                {
                                    alias genFunc = genData_;
                                }

                            }

                            engine.runEngine!(MetaT, genInd,
                                    genFunc)(metaExecutionState, bench.measurementList);
                        }
                        else
                        {
                            //It's not a type, so it better be a range literal.
                            //Arrays are special cased
                            alias specRangeT = typeof(paramItem);
                            //pragma(msg, isInputRange!specRangeT);
                            static assert(isInputRange!specRangeT
                                    && !isInfinite!(specRangeT), "not a valid parameter");
                            //It's a range 
                            alias ElemT = ElementType!specRangeT;
                            //pragma(msg, ElemT);
                            
                            static assert(__traits(compiles, symbol!(ElemT.init)),
                                    " symbol = " ~ fullyQualifiedName!symbol);
                            import std.array : array;
                            enum ctRange = paramItem.array;

                            static foreach (ctRangeItem; ctRange)
                            {
                                {
                                    alias func = symbol!ctRangeItem;

                                    auto bench = theFunctionBench;
                                    static if(isSomeString!(typeof(ctRangeItem)))
                                        enum stringSummary = ctRangeItem;
                                    else 
                                        enum stringSummary = ctRangeItem.stringof;
                                    //Run the benchmark
                                    alias engine = DefaultExecutionEngine!(
                                            theFunctionBench.benchmarkName ~ stringSummary, func);
                                    enum forwardTemplateParam = bench.forward;
                                    alias genInd = bench.genIndSet;
                                    alias genData_ = bench.genData;
                                    alias IndT = ElementType!(typeof(genInd));

                                    static if (__traits(isTemplate, genData_))
                                    {
                                        static assert(__traits(compiles, genData_!IndT));
                                        alias genFunc = genData_!IndT;
                                    }
                                    else
                                    {
                                        static if (forwardTemplateParam)
                                        {
                                            alias genFunc = genData_.contents!paramItem;
                                        }
                                        else
                                        {
                                            alias genFunc = genData_;
                                        }
                                    }
                                    engine.runEngine!(MetaT, genInd,
                                        genFunc)(metaExecutionState, bench.measurementList);
                                }
                                
                            }

                        }

                    }
                }
                //A parameter can be a range, don't forget

                //Can't introspect over the number of template parameters realistically. 
            }
            else
            {
                //It's a function benchmark
                //To find out how many there are

                auto bench = theFunctionBench;
                //static assert(!is(ReturnType!symbol == void), "benchmarked function may not (yet) be void. Support for ref args coming soon");
                //Run the benchmark
                alias engine = DefaultExecutionEngine!(theFunctionBench.benchmarkName, symbol);
                alias genInd = bench.genIndSet;
                alias genData_ = bench.genData;
                alias IndT = ElementType!(typeof(genInd));

                static if (__traits(isTemplate, genData_))
                {
                    static assert(__traits(compiles, genData_!IndT));
                    alias genFunc = genData_!IndT;
                }
                else
                {
                    alias genFunc = genData_;
                }

                engine.runEngine!(MetaT, genInd, genFunc)(metaExecutionState,
                        bench.measurementList);
            }

        }

    }

}

///
unittest
{
    @trusted auto getStdoutRange()
    {
        import std.stdio : stdout;

        return stdout.lockingTextWriter;
    }
    //Lump the benchmarks together somewhere.
    static class StaticStore
    {

        import kernels;
        import measurement;
        import std.range : iota, repeat;
        import std.random : uniform;

        enum meas = [PhobosTimer("A stub").toMeasurement];

        @FunctionBenchmark!("Something with an integer", iota(1, 50), (x) => uniform(-x, x))(meas) static void func(
                int l)
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

        @TemplateBenchmark!(0, int, float, double) @FunctionBenchmark!("Templated add benchmark",
                0.repeat(100), ForwardTemplate!(getRandPair))(meas) static T templatedAdd(T)(T x,
                T y)
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
