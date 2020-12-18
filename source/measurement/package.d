module chimpfella.measurement;
public import chimpfella.measurement.phobostimer;
import sumtype;

public alias Measurements = SumType!(PhobosTimer);
public alias StateTypes = SumType!(PhobosTimer.StateT);

//SumType operations are spelled out explicitly to make it more obvious

Measurements toMeasurement(T)(T x) pure
{
    Measurements tmp;
    tmp = x;
    return tmp;
}

@safe StateTypes getState(Measurements fromThis)
{
    return StateTypes(fromThis.match!((ref PhobosTimer f) => f.getState()));
}

@safe auto getHeader(Measurements fromThis)
{
    return (fromThis.match!((ref PhobosTimer f) => f.getHeader()));
}
@safe auto procMeas(alias func)(ref const Measurements fromThis)
{
    return fromThis.match!((const ref PhobosTimer f) => func(f));
}
@safe auto procState(alias func)(ref StateTypes fromThis)
{
    return fromThis.match!((ref PhobosTimer.StateT f) => func(f));
}
