module SparseBenchmarks

include(joinpath(dirname(@__FILE__), "..", "utils", "RandUtils.jl"))

using .RandUtils
using BenchmarkTools
using SparseArrays
using LinearAlgebra

const SUITE = BenchmarkGroup(["array"])

#########
# index #
#########

# Note that some of the "logical" tests are commented
# out because they require resolution of JuliaLang/julia#14717.

g = addgroup!(SUITE, "index")

# vector #
#--------#

sizes = (10^3, 10^4, 10^5)

spvecs = map(s -> samesprand(s, inv(sqrt(s))), sizes)
splogvecs = map(s -> samesprandbool(s, 1e-5), sizes)

for (s, v, l) in zip(sizes, spvecs, splogvecs)
    g["spvec", "array",   s] = @benchmarkable getindex($v, $(samerand(1:s, s)))
    g["spvec", "integer", s] = @benchmarkable getindex($v, $(samerand(1:s)))
    g["spvec", "range",   s] = @benchmarkable getindex($v, $(1:s))
    g["spvec", "logical", s] = @benchmarkable getindex($v, $(samerand(Bool, s)))
    # g["spvec", "splogical", s, nnz(v), nnz(l)] = @benchmarkable getindex($v, $l)
end

# matrix #
#--------#

sizes = (10, 10^2, 10^3)
inds = map(s -> samerand(1:s), sizes)
matrices = map(s -> samesprand(s, s, inv(sqrt(s))), sizes)
vectors = map(s -> samerand(1:s, s), sizes)
logvecs = map(s -> samerand(Bool, s), sizes)
splogmats = map(s -> samesprandbool(s, s, 1e-5), sizes)
splogvecs = map(s -> samesprandbool(s, 1, 1e-5), sizes)

for (s, m, v, l, sl, c) in zip(sizes, matrices, vectors, logvecs, splogvecs, inds)
    g["spmat", "col", "array", s] = @benchmarkable getindex($m, $v, $c)
    g["spmat", "col", "range", s] = @benchmarkable getindex($m, $(1:s), $c)
    g["spmat", "col", "OneTo", s] = @benchmarkable getindex($m, $(Base.OneTo(s)), $c)
    g["spmat", "col", "logical", s] = @benchmarkable getindex($m, $l, $c)
    # g["spmat", "col", "splogical", s] = @benchmarkable getindex($m, $sl, $c)
end

for (s, m, v, l, sl, r) in zip(sizes, matrices, vectors, logvecs, splogvecs, inds)
    g["spmat", "row", "array", s] = @benchmarkable getindex($m, $r, $v)
    g["spmat", "row", "range", s] = @benchmarkable getindex($m, $r, $(1:s))
    g["spmat", "row", "OneTo", s] = @benchmarkable getindex($m, $r, $(Base.OneTo(s)))
    g["spmat", "row", "logical", s] = @benchmarkable getindex($m, $r, $l)
    # g["spmat", "row", "splogical", s] = @benchmarkable getindex($m, $r, $sl)
end

for (s, m, v, l, sl, i) in zip(sizes, matrices, vectors, logvecs, splogmats, inds)
    g["spmat", "array", s] = @benchmarkable getindex($m, $v, $v)
    g["spmat", "integer", s] = @benchmarkable getindex($m, $i, $i)
    g["spmat", "range", s] = @benchmarkable getindex($m, $(1:s), $(1:s))
    g["spmat", "OneTo", s] = @benchmarkable getindex($m, $(Base.OneTo(s)), $(Base.OneTo(s)))
    g["spmat", "logical", s] = @benchmarkable getindex($m, $l, $l)
    g["spmat", "splogical", s] = @benchmarkable getindex($m, $sl)
end

for b in values(g)
    b.params.time_tolerance = 0.3
end

######################
# transpose (#14631) #
######################

small_sqr = samesprand(600, 600, 0.01)
small_rct = samesprand(600, 400, 0.01)
large_sqr = samesprand(20000, 20000, 0.01)
large_rct = samesprand(20000, 10000, 0.01)

g = addgroup!(SUITE, "transpose", ["adjoint"])

for m in (small_sqr, small_rct, large_sqr, large_rct)
    cm = m + m*im
    s = size(m)
    g["transpose", s] = @benchmarkable transpose($m)
    g["transpose!", s] = @benchmarkable transpose!($(copy(transpose(m))), $m)
    g["adjoint", s] = @benchmarkable adjoint($cm)
    g["adjoint!", s] = @benchmarkable adjoint!($(copy(transpose(cm))), $cm)
end

for b in values(g)
    b.params.time_tolerance = 0.3
end

##############
# arithmetic #
##############

g = addgroup!(SUITE, "arithmetic")

# unary minus, julialang repo issue #19503 / fix #19530
g["unary minus", size(small_sqr)] = @benchmarkable -$small_sqr
g["unary minus", size(large_sqr)] = @benchmarkable -$large_sqr

for b in values(g)
    b.params.time_tolerance = 0.3
end

################
# constructors #
################
g = addgroup!(SUITE, "constructors")

const UPLO = :U
for s in sizes
    nz = floor(Int, 1e-4*s*s)
    I = samerand(1:s, nz)
    J = samerand(1:s, nz)
    V = randvec(nz)
    g["IV", s] = @benchmarkable sparsevec($I, $V)
    g["IJV", s] = @benchmarkable sparse($I, $J, $V)
    g["Diagonal", s] = @benchmarkable sparse($(Diagonal(randvec(s))))
    g["Bidiagonal", s] = @benchmarkable sparse($(Bidiagonal(randvec(s), randvec(s-1), UPLO)))
    g["Tridiagonal", s] = @benchmarkable sparse($(Tridiagonal(randvec(s-1), randvec(s), randvec(s-1))))
    g["SymTridiagonal", s] = @benchmarkable sparse($(SymTridiagonal(randvec(s), randvec(s-1))))
end

#########################
# matrix multiplication #
#########################

g = addgroup!(SUITE, "matmul")

# mixed sparse-dense matmul #
#---------------------------#

using LinearAlgebra: *, mul!

function allocmats_ds(om, ok, on, s, nnzc, T)
    m, k, n = map(x -> Int(s*x), (om, ok, on))
    densemat, sparsemat = samerand(T, m, k), samesprand(T, k, n, nnzc/k)
    tdensemat = transpose!(similar(densemat, reverse(size(densemat))), densemat)
    tsparsemat = transpose!(similar(sparsemat, reverse(size(sparsemat))), sparsemat)
    destmat = similar(densemat, m, n)
    return m, k, n, destmat,
        densemat, sparsemat,
        tdensemat, tsparsemat
end
function allocmats_sd(om, ok, on, s, nnzc, T)
    m, k, n = map(x -> Int(s*x), (om, ok, on))
    densemat, sparsemat = samerand(T, k, m), samesprand(T, n, k, nnzc/n)
    tdensemat = transpose!(similar(densemat, reverse(size(densemat))), densemat)
    tsparsemat = transpose!(similar(sparsemat, reverse(size(sparsemat))), sparsemat)
    destmat = similar(densemat, n, m)
    return m, k, n, destmat,
        densemat, sparsemat,
        tdensemat, tsparsemat
end

for (om, ok, on) in (# order of matmul dimensions m, k, and n
        (10^2, 10^2, 10^2),  # dense square * sparse square -> dense square
        (10^1, 10^1, 10^3),  # dense square * sparse short -> dense short
        (10^2, 10^2, 10^1),  # dense square * sparse tall -> dense tall
        (10^1, 10^3, 10^3),  # dense short * sparse square -> dense short
        (10^1, 10^2, 10^3),  # dense short * sparse short -> dense short
        (10^1, 10^3, 10^2),  # dense short * sparse tall -> dense short
        (10^3, 10^1, 10^1),  # dense tall * sparse square -> dense tall
        (10^2, 10^1, 10^2),  # dense tall * sparse short -> dense square
        ) # the preceding descriptions apply to dense-sparse matmul without
          # any transpositions. other cases are described below
    #
    # the transpose and adjoint variants share kernel code
    # the in-place and out-of-place variants share kernel code
    # so exercise the different variants in different ways
    #
    # for A[t|c]_mul_B[t|c][!]([dense,], dense, sparse) kernels,
    # the dense matrix is m-by-k, or k-by-m for A(c|t) operations
    # the sparse matrix is k-by-n, or n-by-k for B(c|t) operations
    # and the (dense) destination matrix is m-by-n in any case
    # the sparse matrix has approximately 10 entries per column
    #
    # # out-of-place dense-sparse ops, transpose variants, i.e. A[t]_mul_B[t](dense, sparse)
    m, k, n, destmat, densemat, sparsemat, tdensemat, tsparsemat = allocmats_ds(om, ok, on, 1/2, 4, Float64)
    g["A_mul_B",   "dense $(m)x$(k), sparse $(k)x$(n) -> dense $(m)x$(n)"] = @benchmarkable *($densemat, $sparsemat)
    g["A_mul_Bt",  "dense $(m)x$(k), sparse $(n)x$(k) -> dense $(m)x$(n)"] = @benchmarkable *($densemat, $(Transpose(tsparsemat)))
    g["At_mul_B",  "dense $(k)x$(m), sparse $(k)x$(n) -> dense $(m)x$(n)"] = @benchmarkable *($(Transpose(tdensemat)), $sparsemat)
    g["At_mul_Bt", "dense $(k)x$(m), sparse $(n)x$(k) -> dense $(m)x$(n)"] = @benchmarkable *($(Transpose(tdensemat)), $(Transpose(tsparsemat)))
    # in-place dense-sparse -> dense ops, transpose variants, i.e. A[t]_mul[t]!(dense, dense, sparse)
    m, k, n, destmat, densemat, sparsemat, tdensemat, tsparsemat = allocmats_ds(om, ok, on, 4, 12, Float64)
    g["A_mul_B!",   "dense $(m)x$(k), sparse $(k)x$(n) -> dense $(m)x$(n)"] = @benchmarkable mul!($destmat, $densemat, $sparsemat)
    g["A_mul_Bt!",  "dense $(m)x$(k), sparse $(n)x$(k) -> dense $(m)x$(n)"] = @benchmarkable mul!($destmat, $densemat, $(Transpose(tsparsemat)))
    g["At_mul_B!",  "dense $(k)x$(m), sparse $(k)x$(n) -> dense $(m)x$(n)"] = @benchmarkable mul!($destmat, $(Transpose(tdensemat)), $sparsemat)
    g["At_mul_Bt!", "dense $(k)x$(m), sparse $(n)x$(k) -> dense $(m)x$(n)"] = @benchmarkable mul!($destmat, $(Transpose(tdensemat)), $(Transpose(tsparsemat)))
    # out-of-place dense-sparse ops, adjoint variants, i.e. A[c]_mul_B[c](dense, sparse)
    m, k, n, destmat, densemat, sparsemat, tdensemat, tsparsemat = allocmats_ds(om, ok, on, 1/2, 4, Complex{Float64})
    g["A_mul_Bc",  "dense $(m)x$(k), sparse $(n)x$(k) -> dense $(m)x$(n)"] = @benchmarkable *($densemat, $(Adjoint(tsparsemat)))
    g["Ac_mul_B",  "dense $(k)x$(m), sparse $(k)x$(n) -> dense $(m)x$(n)"] = @benchmarkable *($(Adjoint(tdensemat)), $sparsemat)
    g["Ac_mul_Bc", "dense $(k)x$(m), sparse $(n)x$(k) -> dense $(m)x$(n)"] = @benchmarkable *($(Adjoint(tdensemat)), $(Adjoint(tsparsemat)))
    # in-place dense-sparse -> dense ops, adjoint variants, i.e. A[c]_mul[c]!(dense, dense, sparse)
    m, k, n, destmat, densemat, sparsemat, tdensemat, tsparsemat = allocmats_ds(om, ok, on, 2, 8, Complex{Float64})
    g["A_mul_Bc!",  "dense $(m)x$(k), sparse $(n)x$(k) -> dense $(m)x$(n)"] = @benchmarkable mul!($destmat, $densemat, $(Adjoint(tsparsemat)))
    g["Ac_mul_B!",  "dense $(k)x$(m), sparse $(k)x$(n) -> dense $(m)x$(n)"] = @benchmarkable mul!($destmat, $(Adjoint(tdensemat)), $sparsemat)
    g["Ac_mul_Bc!", "dense $(k)x$(m), sparse $(n)x$(k) -> dense $(m)x$(n)"] = @benchmarkable mul!($destmat, $(Adjoint(tdensemat)), $(Adjoint(tsparsemat)))
    #
    # for A[t|c]_mul_B[t|c][!]([dense,], sparse, dense) kernels,
    # the sparse matrix is n-by-k, or k-by-n for B(c|t) operations
    # the dense matrix is k-by-m, or m-by-k for A(c|t) operations
    # and the (dense) destination matrix is n-by-m in any case
    # the sparse matrix has approximately 10 entries per column
    #
    # out-of-place sparse-dense ops, transpose variants, i.e. A[t]_mul_B[t](sparse, dense)
    m, k, n, destmat, densemat, sparsemat, tdensemat, tsparsemat = allocmats_sd(om, ok, on, 1/2, 4, Complex{Float64})
    g["A_mul_B",   "sparse $(n)x$(k), dense $(k)x$(m) -> dense $(n)x$(m)"] = @benchmarkable *($sparsemat, $densemat)
    g["A_mul_Bt",  "sparse $(n)x$(k), dense $(m)x$(k) -> dense $(n)x$(m)"] = @benchmarkable *($sparsemat, $(Transpose(tdensemat)))
    g["At_mul_B",  "sparse $(k)x$(n), dense $(k)x$(m) -> dense $(n)x$(m)"] = @benchmarkable *($(Transpose(tsparsemat)), $densemat)
    g["At_mul_Bt", "sparse $(k)x$(n), dense $(m)x$(k) -> dense $(n)x$(m)"] = @benchmarkable *($(Transpose(tsparsemat)), $(Transpose(tdensemat)))
    # in-place sparse-dense -> dense ops, transpose variants, i.e. A[t|c]_mul_B[t|c]!(dense, sparse, dense)
    m, k, n, destmat, densemat, sparsemat, tdensemat, tsparsemat = allocmats_sd(om, ok, on, 4, 12, Complex{Float64})
    g["A_mul_B!",   "sparse $(n)x$(k), dense $(k)x$(m) -> dense $(n)x$(m)"] = @benchmarkable mul!($destmat, $sparsemat, $densemat)
    g["A_mul_Bt!",  "sparse $(n)x$(k), dense $(m)x$(k) -> dense $(n)x$(m)"] = @benchmarkable mul!($destmat, $sparsemat, $(Transpose(tdensemat)))
    g["At_mul_B!",  "sparse $(k)x$(n), dense $(k)x$(m) -> dense $(n)x$(m)"] = @benchmarkable mul!($destmat, $(Transpose(tsparsemat)), $densemat)
    g["At_mul_Bt!", "sparse $(k)x$(n), dense $(m)x$(k) -> dense $(n)x$(m)"] = @benchmarkable mul!($destmat, $(Transpose(tsparsemat)), $(Transpose(tdensemat)))
    # out-of-place sparse-dense ops, adjoint variants, i.e. A[c]_mul_B[c](sparse, dense)
    m, k, n, destmat, densemat, sparsemat, tdensemat, tsparsemat = allocmats_sd(om, ok, on, 1/2, 4, Complex{Float64})
    g["A_mul_Bc",  "sparse $(n)x$(k), dense $(m)x$(k) -> dense $(n)x$(m)"] = @benchmarkable *($sparsemat, $(Adjoint(tdensemat)))
    g["Ac_mul_B",  "sparse $(k)x$(n), dense $(k)x$(m) -> dense $(n)x$(m)"] = @benchmarkable *($(Adjoint(tsparsemat)), $densemat)
    g["Ac_mul_Bc", "sparse $(k)x$(n), dense $(m)x$(k) -> dense $(n)x$(m)"] = @benchmarkable *($(Adjoint(tsparsemat)), $(Adjoint(tdensemat)))
    # in-place sparse-dense -> dense ops, adjoint variants, i.e. A[t|c]_mul_B[t|c]!(dense, sparse, dense)
    m, k, n, destmat, densemat, sparsemat, tdensemat, tsparsemat = allocmats_sd(om, ok, on, 2, 8, Complex{Float64})
    g["A_mul_Bc!",  "sparse $(n)x$(k), dense $(m)x$(k) -> dense $(n)x$(m)"] = @benchmarkable mul!($destmat, $sparsemat, $(Adjoint(tdensemat)))
    g["Ac_mul_B!",  "sparse $(k)x$(n), dense $(k)x$(m) -> dense $(n)x$(m)"] = @benchmarkable mul!($destmat, $(Adjoint(tsparsemat)), $densemat)
    g["Ac_mul_Bc!", "sparse $(k)x$(n), dense $(m)x$(k) -> dense $(n)x$(m)"] = @benchmarkable mul!($destmat, $(Adjoint(tsparsemat)), $(Adjoint(tdensemat)))
end

for b in values(g)
    b.params.time_tolerance = 0.3
end


#################
# sparse matvec #
#################
g = addgroup!(SUITE, "sparse matvec")
B = randn(100000, 100)
A = sprand(100000, 100000, 0.00001)
g["non-adjoint"] = @benchmarkable A * B
g["adjoint"] = @benchmarkable A' * B

#################
# sparse solves #
#################
g = addgroup!(SUITE, "sparse solves")
# Problem similar to issue #30288
let m = 10000, n = 9000
    A = spdiagm(0 => fill(2.0, m),
               -1 => fill(1.0, m - 1),
                1 => fill(1.0, m - 1),
              360 => fill(1.0, m - 360))[:, 1:n]
    AtA = A'A
    b   = ones(m)
    B   = ones(m, 2)
    Atb = A'b
    AtB = A'B

    g["least squares (default), vector rhs"]  = @benchmarkable         $A\$b
    g["least squares (default), matrix rhs"]  = @benchmarkable         $A\$B
    g["least squares (qr), vector rhs"]   = @benchmarkable     qr($A)\$b
    g["least squares (qr), matrix rhs"]   = @benchmarkable     qr($A)\$B
    g["square system (default), vector rhs"]  = @benchmarkable       $AtA\$Atb
    g["square system (default), matrix rhs"]  = @benchmarkable       $AtA\$AtB
    g["square system (ldlt), vector rhs"] = @benchmarkable ldlt($AtA)\$Atb
    g["square system (ldlt), matrix rhs"] = @benchmarkable ldlt($AtA)\$AtB
    g["square system (lu), vector rhs"]   = @benchmarkable   lu($AtA)\$Atb
    g["square system (lu), matrix rhs"]   = @benchmarkable   lu($AtA)\$AtB
end

end # module
