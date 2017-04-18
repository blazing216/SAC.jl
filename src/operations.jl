# Trace operations

"""
    add!(::SACtr, value)

Add a constant value to a SAC trace
"""
function add!(a::Array{SACtr}, val)
    for s in a s.t[:] = s.t[:] + val end
    update_headers!(a)
end
add!(s::SACtr, val) = add!([s], val)

"""
    cut!(s::SACtr, b::Number, e::Number)
    cut!(s::Array{SACtr}, b::Number, e::Number)

Cut a trace or array of traces `s` in memory between times `b` and `e`, relative
to the O marker.

    cut!(s::Array{SACtr}, a::Array, b::Array)

Cut the array of traces `s` between the times in arrays `b` and `e`, which must be
the same length as `s`.
"""
function cut!(s::SACtr, b::Real, e::Real)
    if b < s.b
        info("SAC.cut!: beginning cut is before start of trace.  Setting to $(s.b).")
        b = s.b
    end
    b > s.e && error("SAC.cut!: end cut time is later than end of trace.")
    if e > s.e
        info("SAC.cut!: end cut is after end of trace.  Setting to $(s.e).")
        e = s.e
    end
    e < s.b && error("SAC.cut!: end time is earlier than start of trace.")
    ib = round(Int, (b - s.b)/s.delta) + 1
    ie = s.npts - round(Int, (s.e - e)/s.delta)
    s.t = s.t[ib:ie]
    s.b, s.e = s.b + (ib - 1)*s.delta, s.b + (ie - 1)*s.delta
    s.npts = ie - ib + 1
    update_headers!(s)
end

# Array version of cut!
function cut!(a::Array{SACtr}, b::Number, e::Number)
    for s in a
        SAC.cut!(s, b, e)
    end
    a
end

function cut!{B<:Real,E<:Real}(a::Array{SACtr}, b::Array{B}, e::Array{E})
    @assert length(a) == length(b) == length(e) "Arrays `a`, `b` and `e` must be the same length"
    for (s, beg, en) in zip(a, b, e)
        SAC.cut!(s, beg, en)
    end
    a
end

"""
    differentiate!(s::SACtr, npoints::Integer=2)

Differentiate the SAC trace `s`, replacing it with its time derivative `dsdt`.
Select the mode of numerical differentiation with `npoints`.

### Available algorithms

- `npoints == 2`: Two-point.  `dsdt.t[i] = (s.t[i+1] - s.t[i])/s.delta`.
  Non-central difference, so `s.b` is increased by half `s.delta`.  `npts` is
  reduced by 1.
- `npoints == 3`: Three-point. `dsdt.t[i] = (s.t[i+1] - s.t[i-1])/(2 * s.delta)`.
  Central difference.  `s.b` is increased by `s.delta`; `npts` reduced by 2.
- `npoints == 3`: Five-point. `dsdt.t[i] =
  (2/3)*(s.t[i+1] - s.t[i-1])/s.delta - (1/12)*(s.t[i+2] - s.t[i-2])/s.delta`.
  Central difference.  `s.b` is increased by `2s.delta`; `npts` reduced by 4.
"""
function differentiate!(s::SACtr, npoints::Integer=2)
    npoints in (2, 3, 5) ||
        throw(ArgumentError("`npoints` cannot be $(npoints); must be one of (2, 3, 5)"))
    if npoints == 2
        t = Vector{SACFloat}(s.npts - 1)
        @inbounds for i in 1:(s.npts-1)
            s.t[i] = (s.t[i+1] - s.t[i])/s.delta
        end
        pop!(s.t)
        s.npts -= 1
        s.b += s.delta/2
    elseif npoints == 3
        @inbounds for i in 2:(s.npts-1)
            s.t[i-1] = (s.t[i+1] - s.t[i-1])/(2*s.delta)
        end
        pop!(s.t); pop!(s.t)
        s.npts -= 2
        s.b += s.delta
    elseif npoints == 5
        t1 = (s.t[3] - s.t[1])/(2*s.delta)
        t2 = (s.t[end] - s.t[end-2])/(2*s.delta)
        d1 = 2/(3*s.delta)
        d2 = 1/(12*s.delta)
        t_minus_2 = s.t[1]
        t_minus_1 = s.t[2]
        t = s.t[3]
        t_plus_1 = s.t[4]
        @inbounds for i in 2:(s.npts-3)
            t_plus_2 = s.t[i+3]
            s.t[i] = d1*(t_plus_1 - t_minus_1) - d2*(t_plus_2 - t_minus_2)
            t_minus_2 = t_minus_1
            t_minus_1 = t
            t = t_plus_1
            t_plus_1 = t_plus_2
        end
        s.t[1] = t1
        s.t[end-2] = t2
        pop!(s.t); pop!(s.t)
        s.npts -= 2
        s.b += s.delta
    end
    update_headers!(s)
end
const diff! = differentiate!

"""
    divide!(::SACtr, value)

Divide the values in a SAC trace by `value`
"""
function divide!(a::Array{SACtr}, value)
    value != 0. || error("SAC.divide!: Cannot divide by 0")
    multiply!(a, 1./value)
end
divide!(s::SACtr, value) = divide!([s], value)
const div! = divide!

"""
    envelope!(::SACtr)

Find the envelope of a SAC trace
"""
function envelope!(a::Array{SACtr})
    for s in a
        s.t = abs(DSP.hilbert(s.t))
    end
    update_headers!(a)
end
envelope!(s::SACtr) = envelope!([s])

"""
    fft(s::SACtr) -> f, S

Return the Fourier-transformed trace from `s` as `S`, with the frequencies
which correspond to each point in `f`.
"""
function fft(s::SACtr)
    # Return the fourier-transformed trace and the frequencies to go along with it
    N = round(Int, s.npts/2) + 1
    fmax = 1./(s.npts*s.delta)
    f = collect(1:N)*fmax
    S = Base.fft(s.t)[1:N]
    return f, S
end

function fft(a::Array{SACtr})
    # Return arrays containing f and S for an array of SACtr objects
    n = length(a)
    f, S = Array(Array, n), Array(Array, n)
    for i = 1:n
        f[i], S[i] = fft(a[i])
    end
    return f, S
end

"""
    integrate!(s::SACtr, method=:trapezium)

Replace `s` with its time-integral.  This is done by default using the trapezium rule.
Use `method=:rectangle` to use the rectangle rule.

If `method==:trapezium` (the default), then `s.npts` is reduced by one and `s.b` is
increased by `s.delta/2`.
"""
function integrate!(s::SACtr, method::Symbol=:trapezium)
    method in (:trapezium, :rectangle) ||
        throw(ArgumentError("`methodod` must by one of `:trapezium` or `:rectangle` " *
                            "(got '$method')"))
    if method == :trapezium
        total = zero(s.t[1])
        h = s.delta/2
        @inbounds for i in 1:(s.npts-1)
            total += h*(s.t[i] + s.t[i+1])
            s.t[i] = total
        end
        s.npts -= 1
        pop!(s.t)
        s.b += s.delta/2
    elseif method == :rectangle
        h = s.delta
        @inbounds for i in 2:s.npts
            s.t[i] = h*s.t[i] + s.t[i-1]
        end
    end
    update_headers!(s)
end
const int! = integrate!

"""
    interpolate!(::SACtr, npts=npts)
    interpolate!(::SACtr, delta=delta)
    interpolate!(::SACtr, n=n)

Resample a SAC trace by supplying one of three things:

* A new number of samples (`npts`)
* A new sampling interval (`delta` in seconds)
* A multiple by which to increase the sampling (`n`)

Interpolation is performed using quadratic splines using the `Dierckx` package.
"""
function interpolate!(s::SACtr; npts::Integer=0, delta::Real=0.0, n::Integer=0)
    isdefined(:Dierckx) || @eval import Dierckx
    # Calculate new points at which to evaluate time series
    interp_t = if npts != 0
        npts >= 0 || error("`npts` cannot be negative")
        delta = (s.e - s.b)/(npts - 1)
        s.b + (0:(npts-1))*delta
    elseif delta != 0.0
        delta >= 0.0 || error("`delta` cannot be negative")
        delta < (s.e - s.b) || error("`delta`")
        times = s.b:delta:s.e
        npts = length(times)
        times
    elseif n != 0
        n > 0 || error("`n` cannot be negative")
        npts = (s.npts - 1)*n + 1
        delta = (s.e - s.b)/(npts - 1)
        s.b + (0:(npts-1))*delta
    else
        error("Must supply one keyword argument of `npts`, `n` or `delta`")
    end
    @assert npts == length(interp_t)
    # Create fit using degree-2 Bsplines
    spl = Dierckx.Spline1D(SAC.time(s), s.t, k=2)
    s.t = Dierckx.evaluate(spl, interp_t)
    s.npts = npts
    s.delta = delta
    update_headers!(s)
end

"""
    multiply!(::SACtr, value)
    mul!(::SACtr, value)

Multiply the values in a SAC trace by `value`
"""
function multiply!(a::Array{SACtr}, val)
    for s in a s.t[:] = s.t[:]*val end
    update_headers!(a)
end
multiply!(s::SACtr, val) = multiply!([s], val)
const mul! = multiply!

"""
    rmean!(::SACtr)

Remove the mean in-place for a SAC trace.
"""
function rmean!(s::SACtr)
    # Remove the mean in-place
    s.t = s.t - mean(s.t)
    update_headers!(s)
end
function rmean!(a::Array{SACtr})
    for s in a
        rmean!(s)
    end
    a
end

"""
    rotate_through!(::SACtr, ::SACtr, phi)
    rotate_through!(::Array{SACtr}, phi)

In the first form, with two SAC traces which are horizontal and orthgonal, rotate
them *clockwise* by `phi`° about the vertical axis.

In the second form, rotate each sequential pair of traces (i.e., indices 1 and 2,
3 and 4, ..., end-1 and end).

This is a reference frame transformation (passive rotation) and hence particle motion
will appear to rotate anti-clockwise.
"""
function rotate_through!(s1::SACtr, s2::SACtr, phi)
    if !(mod(abs(s2.cmpaz - s1.cmpaz), SACFloat(180)) ≈ SACFloat(90))
        error("SAC.rotate_through!: traces must be orthogonal")
    elseif s1.npts != s2.npts
        error("SAC.rotate_through!: traces must be same length")
    elseif s1.delta != s2.delta
        error("SAC.rotate_through!: traces must have same delta")
    end
    phir = deg2rad(phi)
    R = [cos(phir) sin(phir);
        -sin(phir) cos(phir)]
    for i = 1:s1.npts
        (s1.t[i], s2.t[i]) = R*[s1.t[i]; s2.t[i]]
    end
    for t in (s1, s2)
        setfield!(t, :cmpaz, SAC.SACFloat(mod(getfield(t, :cmpaz) + phi, 360.)))
        setfield!(t, :kcmpnm, SAC.sacstring(getfield(t, :cmpaz)))
        SAC.update_headers!(t)
    end
    s1, s2
end
function rotate_through!(a::Array{SACtr}, phi)
    length(a)%2 != 0 && error("SAC.rotate_through!: Array of traces must be a multiple of two long")
    for i = 1:length(a)÷2
        rotate_through!(a[2*i - 1], a[2*i], phi)
    end
    a
end

"""
    rotate_through(s1::SACtr, s2::SACtr, phi) -> new_s1, new_s2

Copying version of `rotate_through` which returns modified versions of the traces
in `s1` and `s2`, leaving the originals unaltered.  See docs of `rotate_through!` for details.
"""
function rotate_through(s1::SACtr, s2::SACtr, phi)
    s1_new, s2_new = deepcopy(s1), deepcopy(s2)
    rotate_through!(s2, s2, phi)
    s1_new, s2_new
end
rotate_through(a::Array{SACtr}, phi) =
    rotate_through(@view(s1[1:2:end]), @view(s2[2:2:end]), phi)

"""
    rtrend!(::SACtr)

Remove the trend from a SAC trace in place.
"""
function rtrend!(s::SACtr)
    # Remove the trend in-place
    t = time(s)
    x0, x1 = linreg(t, s.t)
    s.t = s.t - (x0 + x1*t)
    update_headers!(s)
end
function rtrend!(a::Array{SACtr})
    for s in a
        rtrend!(s)
    end
    a
end

"""
    taper!(s::SACtr, width=0.05, form=:hanning)
    taper!(S::Array{SACtr}, width=0.05, form=:hanning)

Apply a symmetric taper to each end of the data in SAC trace `s` or traces `S`.

`form` may be one of `:hanning`, `:hamming` or `:cosine`.

`width` represents the fraction (at both ends) of the trace tapered, up to 0.5.
"""
function taper!(s::SACtr, width=0.05, form=:hanning::Symbol)
    form in [:hamming, :hanning, :cosine] ||
        error("SAC.taper!: `form` must be one of `:hamming`, `:hanning` or `:cosine`")
    0 < width <= 0.5 || error("SAC.taper!: width must be between 0 and 0.5")
    n = max(2, floor(Int, (s.npts + 1)*width))

    if form in [:hamming, :hanning]
        omega = SAC.SACFloat(pi/n)
        if form == :hanning
            f0 = f1 = SAC.SACFloat(0.50)
        elseif form == :hamming
            f0 = SAC.SACFloat(0.54)
            f1 = SAC.SACFloat(0.46)
        end

        @inbounds for i in 0:n-1
            amp = f0 - f1*cos(omega*SAC.SACFloat(i))
            j = s.npts - i
            s.t[i+1] *= amp
            s.t[j] *= amp
        end
    end

    if form == :cosine
        omega = SAC.SACFloat(pi/(2*n))
        @inbounds for i in 0:n-1
            amp = sin(omega*i)
            j = s.npts - i
            s.t[i+1] *= amp
            s.t[j] *= amp
        end
    end

    SAC.update_headers!(s)
end
taper!(S::Array{SACtr}, width=0.05, form::Symbol=:hamming) =
    (for s in S taper!(s, width, form) end; S)

"""
    tshift!(::SACtr, tshift; wrap=true)

Shift a SAC trace backward in time by `t` seconds.

If `wrap` true (default), then points which move out the back of the trace
are added to the front (and vice versa).  Setting it to false instead pads the
trace with zeroes.
"""
function tshift!(s::SACtr, tshift::Number; wrap=true)
    n = round(Int, tshift/s.delta)
    if n == 0
        sac_verbose && info("SAC.tshift!: t ($tshift) is less than delta ($(s.delta)) so no shift applied")
        return
    end
    s.t = circshift(s.t, n)
    if !wrap
        n > 0 ? s.t[1:n] = 0. : s.t[end+n+1:end] = 0.
    end
    update_headers!(s)
end

"""
    update_headers!(s::SACtr)

Ensure that header values which are based on the trace or other header values
are consistent, such as `depmax`.  Should be called after any operation on the trace
`s.t`.
"""
function update_headers!(s::SACtr)
    s.depmax = maximum(s.t)
    s.depmin = minimum(s.t)
    s.depmen = mean(s.t)
    s.e = s.b + s.delta*(s.npts - 1)
    s
end

function update_headers!(a::Array{SACtr})
    for s in a
        update_headers!(s)
    end
    a
end