using FastFilter, Test, BenchmarkTest
import Base: Fix1

@testset "FastFilter.jl" begin
    ary = map(x -> rand(Bool) ? nothing : x, 1:10_000_000)

    pred(a) = !isnothing(a)
    tran(a) = pred(a) ? a : 0

    @test all(filter(pred, ary) .== fastfilter(pred, ary))
    @test all(replace(tran, ary) .== fastreplace(tran, ary))

    @btime filter($pred, $ary);
    @btime fastfilter($pred, $ary);
    @btime replace($tran, $ary);
    @btime fastreplace($tran, $ary);

    summer(f, ary) = sum(f(ary))

    @test summer(Fix1(filter, pred), ary) == summer(Fix1(fastfilter, pred), ary)
    @test summer(Fix1(replace, pred), ary) == summer(Fix1(fastreplace, pred), ary)

    @btime summer(Fix1(filter, pred), $(ary))
    @btime summer(Fix1(fastfilter, pred), $(ary))
    @btime summer(Fix1(replace, tran), $(ary))
    @btime summer(Fix1(fastreplace, tran), $(ary))

    # type inference failed
    @btime filter($ary) do a
        string(a) != "nothing"
    end
    @btime fastfilter($ary) do a
        string(a) != "nothing"
    end
end
