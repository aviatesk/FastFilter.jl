module FastFilter

@static isdefined(Core.Compiler, :AbstractInterpreter) || error("FastFilter.jl only works with Julia versions 1.6 and higher")

# imports
# =======

import Base:
    uniontypes,
    get_world_counter,
    _methods_by_ftype

import Core:
    Const,
    MethodMatch,
    MethodInstance

import Core.Compiler:
    NativeInterpreter,
    specialize_method,
    InferenceResult,
    InferenceState,
    typeinf,
    widenconst

# utils
# =====

function infer(@nospecialize(tt),
               world = get_world_counter(),
               interp = NativeInterpreter(world),
               )
    mms = _methods_by_ftype(tt, -1, world)
    length(mms) === 1 || return nothing

    mm = first(mms)::MethodMatch

    linfo = specialize_method(mm.method, mm.spec_types, mm.sparams)
    result = InferenceResult(linfo)
    frame = InferenceState(result, #=cached=# true, interp)

    typeinf(interp, frame)

    return result
end

# filter
# ======

function fastfilter(@nospecialize(f), a::Array{T,N}) where {T,N}
    if @generated
        ft = f
        et = T
        isa(et, Union) || return :(filter(f, a))
        ets = uniontypes(et)

        filtered = []
        for et in ets
            tt = Tuple{ft,et}
            result = infer(tt)
            if isa(result, InferenceResult)
                result = result.result
                isa(result, Const) && result.val === false && continue
            end
            push!(filtered, et)
        end
        et′ = Union{filtered...}

        return quote
            j = 1
            b = Vector{$(et′)}(undef, length(a))
            isempty(b) && return b
            fallback = first(b)
            for ai in a
                c = f(ai)
                @inbounds b[j] = (c ? ai : fallback)::$(et′)
                j = ifelse(c, j+1, j)
            end
            resize!(b, j-1)
            sizehint!(b, length(b))
            b
        end
    else
        # fallback when there're not enough type information for code generation
        return filter(f, a)
    end
end

function fastfilter(@nospecialize(pred), s::AbstractSet)
    if @generated
        ft = pred
        et = eltype(s)
        isa(et, Union) || return :(filter(pred, s))
        ets = uniontypes(et)

        filtered = []
        for et in ets
            tt = Tuple{ft,et}
            result = infer(tt)
            if isa(result, InferenceResult)
                result = result.result
                isa(result, Const) && result.val === false && continue
            end
            push!(filtered, et)
        end
        et′ = Union{filtered...}

        return :(Base.mapfilter(pred, push!, s, Set{$(et′)}()))
    else
        return filter(pred, s)
    end
end

function fastreplace(@nospecialize(new::Base.Callable), A; count = nothing)
    if @generated
        # when all elements in `A` aren't guaranteed to be replaced, just fallback
        cnt = count
        count === Nothing || return :(replace(new, A; count))
        fallback = :(replace(new, A; count = typemax(Int)))

        ft = new
        et = eltype(A)
        isa(et, Union) || return fallback
        ets = uniontypes(et)

        replaced = []
        for et in ets
            tt = Tuple{ft,et}
            result = infer(tt)
            isa(result, InferenceResult) || return fallback # unsuccessful inference
            push!(replaced, widenconst(result.result))
        end
        et′ = Union{replaced...}

        return :(Base._replace!(new, Base._similar_or_copy(A, $(et′)), A, Base.check_count(typemax(Int))))
    else
        if isnothing(count)
            count = typemax(Int)
        end
        return replace(new, A; count)
    end
end

export
    fastfilter,
    fastreplace

end
