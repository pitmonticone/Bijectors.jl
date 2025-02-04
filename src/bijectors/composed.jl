###############
# Composition #
###############

"""
    Composed(ts::A)

    ∘(b1::Bijector{N}, b2::Bijector{N})::Composed{<:Tuple}
    composel(ts::Bijector{N}...)::Composed{<:Tuple}
    composer(ts::Bijector{N}...)::Composed{<:Tuple}

where `A` refers to either
- `Tuple{Vararg{<:Bijector{N}}}`: a tuple of bijectors of dimensionality `N`
- `AbstractArray{<:Bijector{N}}`: an array of bijectors of dimensionality `N`

A `Bijector` representing composition of bijectors. `composel` and `composer` results in a
`Composed` for which application occurs from left-to-right and right-to-left, respectively.

Note that all the alternative ways of constructing a `Composed` returns a `Tuple` of bijectors.
This ensures type-stability of implementations of all relating methdos, e.g. `inverse`.

If you want to use an `Array` as the container instead you can do

    Composed([b1, b2, ...])

In general this is not advised since you lose type-stability, but there might be cases
where this is desired, e.g. if you have a insanely large number of bijectors to compose.

# Examples
## Simple example
Let's consider a simple example of `Exp`:
```julia-repl
julia> using Bijectors: Exp

julia> b = Exp()
Exp{0}()

julia> b ∘ b
Composed{Tuple{Exp{0},Exp{0}},0}((Exp{0}(), Exp{0}()))

julia> (b ∘ b)(1.0) == exp(exp(1.0))    # evaluation
true

julia> inverse(b ∘ b)(exp(exp(1.0))) == 1.0 # inversion
true

julia> logabsdetjac(b ∘ b, 1.0)         # determinant of jacobian
3.718281828459045
```

# Notes
## Order
It's important to note that `∘` does what is expected mathematically, which means that the
bijectors are applied to the input right-to-left, e.g. first applying `b2` and then `b1`:
```julia
(b1 ∘ b2)(x) == b1(b2(x))     # => true
```
But in the `Composed` struct itself, we store the bijectors left-to-right, so that
```julia
cb1 = b1 ∘ b2                  # => Composed.ts == (b2, b1)
cb2 = composel(b2, b1)         # => Composed.ts == (b2, b1)
cb1(x) == cb2(x) == b1(b2(x))  # => true
```

## Structure
`∘` will result in "flatten" the composition structure while `composel` and
`composer` preserve the compositional structure. This is most easily seen by an example:
```julia-repl
julia> b = Exp()
Exp{0}()

julia> cb1 = b ∘ b; cb2 = b ∘ b;

julia> (cb1 ∘ cb2).ts # <= different
(Exp{0}(), Exp{0}(), Exp{0}(), Exp{0}())

julia> (cb1 ∘ cb2).ts isa NTuple{4, Exp{0}}
true

julia> Bijectors.composer(cb1, cb2).ts
(Composed{Tuple{Exp{0},Exp{0}},0}((Exp{0}(), Exp{0}())), Composed{Tuple{Exp{0},Exp{0}},0}((Exp{0}(), Exp{0}())))

julia> Bijectors.composer(cb1, cb2).ts isa Tuple{Composed, Composed}
true
```

"""
struct Composed{A, N} <: Bijector{N}
    ts::A
end

Composed(bs::Tuple{Vararg{<:Bijector{N}}}) where N = Composed{typeof(bs),N}(bs)
Composed(bs::AbstractArray{<:Bijector{N}}) where N = Composed{typeof(bs),N}(bs)

# field contains nested numerical parameters
Functors.@functor Composed

isclosedform(b::Composed) = all(isclosedform, b.ts)
up1(b::Composed) = Composed(up1.(b.ts))
function Base.:(==)(b1::Composed{<:Any, N}, b2::Composed{<:Any, N}) where {N}
    ts1, ts2 = b1.ts, b2.ts
    return length(ts1) == length(ts2) && all(x == y for (x, y) in zip(ts1, ts2))
end

"""
    composel(ts::Bijector...)::Composed{<:Tuple}

Constructs `Composed` such that `ts` are applied left-to-right.
"""
composel(ts::Bijector{N}...) where {N} = Composed(ts)

"""
    composer(ts::Bijector...)::Composed{<:Tuple}

Constructs `Composed` such that `ts` are applied right-to-left.
"""
composer(ts::Bijector{N}...) where {N} = Composed(reverse(ts))

# The transformation of `Composed` applies functions left-to-right
# but in mathematics we usually go from right-to-left; this reversal ensures that
# when we use the mathematical composition ∘ we get the expected behavior.
# TODO: change behavior of `transform` of `Composed`?
@generated function ∘(b1::Bijector{N1}, b2::Bijector{N2}) where {N1, N2}
    if N1 == N2
        return :(composel(b2, b1))
    else
        return :(throw(DimensionMismatch("$(typeof(b1)) expects $(N1)-dim but $(typeof(b2)) expects $(N2)-dim")))
    end
end

# type-stable composition rules
∘(b1::Composed{<:Tuple}, b2::Bijector) = composel(b2, b1.ts...)
∘(b1::Bijector, b2::Composed{<:Tuple}) = composel(b2.ts..., b1)
∘(b1::Composed{<:Tuple}, b2::Composed{<:Tuple}) = composel(b2.ts..., b1.ts...)

# type-unstable composition rules
∘(b1::Composed{<:AbstractArray}, b2::Bijector) = Composed(pushfirst!(copy(b1.ts), b2))
∘(b1::Bijector, b2::Composed{<:AbstractArray}) = Composed(push!(copy(b2.ts), b1))
function ∘(b1::Composed{<:AbstractArray}, b2::Composed{<:AbstractArray})
    return Composed(append!(copy(b2.ts), copy(b1.ts)))
end

# if combining type-unstable and type-stable, return type-unstable
function ∘(b1::T1, b2::T2) where {T1<:Composed{<:Tuple}, T2<:Composed{<:AbstractArray}}
    error("Cannot compose compositions of different container-types; ($T1, $T2)")
end
function ∘(b1::T1, b2::T2) where {T1<:Composed{<:AbstractArray}, T2<:Composed{<:Tuple}}
    error("Cannot compose compositions of different container-types; ($T1, $T2)")
end


∘(::Identity{N}, ::Identity{N}) where {N} = Identity{N}()
∘(::Identity{N}, b::Bijector{N}) where {N} = b
∘(b::Bijector{N}, ::Identity{N}) where {N} = b

inverse(ct::Composed) = Composed(reverse(map(inverse, ct.ts)))

# # TODO: should arrays also be using recursive implementation instead?
function (cb::Composed{<:AbstractArray{<:Bijector}})(x)
    @assert length(cb.ts) > 0
    res = cb.ts[1](x)
    for b ∈ Base.Iterators.drop(cb.ts, 1)
        res = b(res)
    end

    return res
end

@generated function (cb::Composed{T})(x) where {T<:Tuple}
    @assert length(T.parameters) > 0
    expr = :(x)
    for i in 1:length(T.parameters)
        expr = :(cb.ts[$i]($expr))
    end
    return expr
end

function logabsdetjac(cb::Composed, x)
    y, logjac = with_logabsdet_jacobian(cb.ts[1], x)
    for i = 2:length(cb.ts)
        y, res_logjac = with_logabsdet_jacobian(cb.ts[i], y)
        logjac += res_logjac
    end

    return logjac
end

@generated function logabsdetjac(cb::Composed{T}, x) where {T<:Tuple}
    N = length(T.parameters)

    expr = Expr(:block)
    sym_y, sym_ladj, sym_tmp_ladj = gensym(:y), gensym(:lady), gensym(:tmp_lady)
    push!(expr.args, :(($sym_y, $sym_ladj) = with_logabsdet_jacobian(cb.ts[1], x)))
    sym_last_y, sym_last_ladj = sym_y, sym_ladj
    for i = 2:N - 1
        sym_y, sym_ladj, sym_tmp_ladj = gensym(:y), gensym(:lady), gensym(:tmp_lady)
        push!(expr.args, :(($sym_y, $sym_tmp_ladj) = with_logabsdet_jacobian(cb.ts[$i], $sym_last_y)))
        push!(expr.args, :($sym_ladj = $sym_tmp_ladj + $sym_last_ladj))
        sym_last_y, sym_last_ladj = sym_y, sym_ladj
    end
    # don't need to evaluate the last bijector, only it's `logabsdetjac`
    sym_ladj, sym_tmp_ladj = gensym(:lady), gensym(:tmp_lady)
    push!(expr.args, :($sym_tmp_ladj = logabsdetjac(cb.ts[$N], $sym_last_y)))
    push!(expr.args, :($sym_ladj = $sym_tmp_ladj + $sym_last_ladj))
    push!(expr.args, :(return $sym_ladj))

    return expr
end


function with_logabsdet_jacobian(cb::Composed, x)
    rv, logjac = with_logabsdet_jacobian(cb.ts[1], x)
    
    for t in cb.ts[2:end]
        rv, res_logjac = with_logabsdet_jacobian(t, rv)
        logjac += res_logjac
    end
    return (rv, logjac)
end

@generated function with_logabsdet_jacobian(cb::Composed{T}, x) where {T<:Tuple}
    expr = Expr(:block)
    sym_y, sym_ladj, sym_tmp_ladj = gensym(:y), gensym(:lady), gensym(:tmp_lady)
    push!(expr.args, :(($sym_y, $sym_ladj) = with_logabsdet_jacobian(cb.ts[1], x)))
    sym_last_y, sym_last_ladj = sym_y, sym_ladj
    for i = 2:length(T.parameters)
        sym_y, sym_ladj, sym_tmp_ladj = gensym(:y), gensym(:lady), gensym(:tmp_lady)
        push!(expr.args, :(($sym_y, $sym_tmp_ladj) = with_logabsdet_jacobian(cb.ts[$i], $sym_last_y)))
        push!(expr.args, :($sym_ladj = $sym_tmp_ladj + $sym_last_ladj))
        sym_last_y, sym_last_ladj = sym_y, sym_ladj
    end
    push!(expr.args, :(return ($sym_y, $sym_ladj)))

    return expr
end
