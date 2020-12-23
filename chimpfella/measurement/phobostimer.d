module chimpfella.measurement.phobostimer;
@safe:
@nogc:
struct PhobosTimer {
    enum MeasurementName = "PhobosTimer";
    size_t eventCount() const
    {
        return 1;
    }
    string[][] getHeader() const {
        static _data = [["PhobosTimer"]];
        return _data;
    }
    import std.datetime.stopwatch;
    public static struct StateT {
        @disable this(this);
        StopWatch timer;
        pragma(inline, true)
        void start()
        {
            timer.start();
        }
        pragma(inline, true)
        void stop()
        {
            timer.stop();
        }
        void read(T)(T[] output) const
        {
            output[0] = timer.peek.total!"nsecs";
        }
    }
    this(string x)
    {

    }
    StateT getState()
    {
        StateT tmp;
        tmp.timer = StopWatch(AutoStart.no);
        return tmp;
    }
}