import Foundation
import Metal

/*
 
 This module should be renamed Bufferable, or some other more fitting name.
 And loader into Model.
 
 Essentially a skeleton of Numpy.
 It has different classes for different dimensionalities, unlike Numpy's single array type,
 because of the static type checking in Swift.
 
 - MTLBufferable is the core class that just holds the MTLBuffer with data.
 - Bufferable<Float> and Bufferable<Float16> are generic arrays. Array would be better fitting, but the name's taken already.
 
 - Scalar = Bufferable<Float16>(shape:[1])
 - ScalarFloat = Bufferable<Float>(shape:[1])
 
 - Vector = Bufferable<Float16>(shape:[rows])
 - VectorFloat = Bufferable<Float>(shape:[rows])

 - Matrix = Bufferable<Float16>(shape:[rows, cols])
 - MatrixFloat = Bufferable<Float>(shape:[rows, cols])

 - Matrix3D = Bufferable<Float16>(shape:[slices, rows, cols])
 - MatrixFloat3D = Bufferable<Float>(shape:[slices, rows, cols])

 - Matrix4D = Bufferable<Float16>(shape:[sliceGroups, slices, rows, cols])
 - MatrixFloat4D = Bufferable<Float>(shape:[sliceGroups, slices, rows, cols])

 The code could also use the following:
 - ScalarInt
 - ScalarLong
 - VectorInt
 - VectorLong

 Right now it's done with typecasting. Needs refactor here.

 The names of functions are inconsistent here and there. Refactor useful.
 
 */

class MTLBufferable {
    var buffer: MTLBuffer
    let offsetBytes: Int
    
    init(buffer: MTLBuffer, offsetBytes: Int = 0) {
        self.buffer = buffer
        self.offsetBytes = offsetBytes
    }
    
    func convertBF16() {
        gpu.deploy("convertBF16X", buffers:[self, self], threadCount: (self as! Bufferable<Float16>).count)
        gpu.eval()
    }
}

private let tmpScalar = ScalarFloat(value: 0)

class Bufferable<Type> : MTLBufferable {
    var bufferPointer: UnsafeMutablePointer<Type> {
        if self._bufferPointer == nil {
            self._bufferPointer = buffer.contents().bindMemory(to: Type.self, capacity: self.shape.reduce(1, *))
        }
        return self._bufferPointer!
    }
    var shape: [Int] // FIX BACK TO LET!
    var rows: Int {self.shape[0]}
    let byteSize: Int
    let bitSize: Int
    var countBytes: Int {self.count * self.byteSize}
    var offsetEls: Int {assert(self.offsetBytes % self.byteSize == 0); return self.offsetBytes/self.byteSize}

    var _bufferPointer : UnsafeMutablePointer<Type>? = nil
    
    var count : Int {
        return self.shape.reduce(1, *)
    }
    
    init(shape: [Int], buffer: MTLBuffer, offset: Int = 0) {
        assert(shape.count > 0)
        assert(shape.reduce(1, *) > 0)

        self.byteSize = MemoryLayout<Type>.size
        self.bitSize = byteSize * 8

        assert((byteSize == 4) || (byteSize == 2), "untested for others")
        self.shape = shape
        super.init(buffer: buffer, offsetBytes: offset*self.byteSize)

    }
    
    convenience init(shape: [Int]) {
        let bufferSize = shape.reduce(1, *) * MemoryLayout<Type>.size
        let _buffer = gpu.device.makeBuffer(length: bufferSize, options: .storageModeShared)!
        self.init(shape: shape, buffer: _buffer)
    }

    convenience init(shape: [Int], with: Type) {
        self.init(shape: shape)
        for i in 0..<self.count {
            self[i] = with
        }
    }
        
    var hasNan : Bool {
        tmpScalar.zero()
        gpu.deploy("hasNan\(bitSize)", buffers: [self, tmpScalar], threadCount: self.count)
        gpu.eval()
        return tmpScalar.val > 0
    }
    
    func save(_ fname: String) {
        let hsaver = TensorSaver(path: "./", model: fname)
        hsaver[0]["h"] = self
        hsaver.save()
    }
    
    func zero() {
        gpu.deploy("zero\(bitSize)", buffers: [self], threadCount: self.count)
    }
    func neg() {
        gpu.deploy("neg\(bitSize)", buffers: [self], threadCount: self.count)
    }
    
    func mul(by s: Scalar) {
        gpu.deploy("mulScalar\(bitSize)x16", buffers:[self, s], threadCount:self.count)
    }

    func mul(by s: ScalarFloat) {
        gpu.deploy("mulScalar\(bitSize)x32", buffers:[self, s], threadCount:self.count)
    }

    
    func add(by buf: Bufferable<Type>) {
        assert(self.shape == buf.shape, "Shapes of both buffers must match")

        gpu.deploy("add\(bitSize)", buffers:[self, buf, self], threadCount: self.count)
    }

    

    func copyFrom(_ src: MTLBufferable, mySize: Bool = false) {
        assert(mySize == true, "no safety checks on buffer sizes, change mySize to true to acknowledge")
        gpu.copyBuffer(src: src, dst: self, size:self.countBytes)
    }
    
    func copyFrom(_ src: Bufferable<Float16>, smallerSize: Bool = false) {
        if !smallerSize {
            assert(src.countBytes == self.countBytes)
        }
        gpu.copyBuffer(src: src, dst: self, size: min(src.countBytes, self.countBytes))
    }
    
    
    func copyFrom(_ src: Bufferable<Float>) {
        assert(src.count == self.count)
        gpu.copyBuffer(src: src, dst: self, size: src.countBytes)
    }
    
    
    
    var str: String {
        return str(10)
    }
    
    
    var strInt: String {
        gpu.eval()
        let _count = count<self.count ? count : self.count
        var outStr = ""
        for i in 0..<_count {
            outStr += "\(self.getInt(index: i)), "
        }
        return outStr
    }
    
    
    func str(_ count: Int? = nil) -> String {
        gpu.eval()
        let _count = count != nil && count!<self.count ? count! : self.count
        var outStr = ""
        for i in 0..<_count {
            outStr += "\(self[i]), "
        }
        return outStr
    }
    
    func getInt(index: Int) -> Int16 {
        var floatStorage: Type
            floatStorage = self[index]

        var intStorage: Int16 = 0

        withUnsafePointer(to: &floatStorage) { floatPointer in
            floatPointer.withMemoryRebound(to: Int16.self, capacity: 1) { intPointer in
                intStorage = intPointer.pointee
            }
        }
        return intStorage
    }
    
    func getLong(index: Int) -> Int {
        var floatStorage: Type
            floatStorage = self[index]

        var intStorage: Int = 0

        withUnsafePointer(to: &floatStorage) { floatPointer in
            floatPointer.withMemoryRebound(to: Int.self, capacity: 1) { intPointer in
                intStorage = intPointer.pointee
            }
        }
        return intStorage
    }

    
    var strInt2: String {
        gpu.eval()
        let _count = count<self.count ? count : self.count
        var outStr = ""
        for i in 0..<_count {
            outStr += "\(self.getInt(index: i)), "
        }
        return outStr
    }
    
    
    
    func getInt2(index: Int) -> Int16 {
        var floatStorage: Type
            floatStorage = self[index]

        var intStorage: Int16 = 0

        withUnsafePointer(to: &floatStorage) { floatPointer in
            floatPointer.withMemoryRebound(to: Int16.self, capacity: 1) { intPointer in
                intStorage = intPointer.pointee
            }
        }
        return intStorage
    }
    
    func zip(_ x: Bufferable<Type>) -> [(Type, Type)] {
        (0..<min(self.count, x.count)).map { (self[$0], x[$0]) }
    }
    
    func zip(_ x: MTLBufferable) -> [(Type, Type)] {
        return zip(x as! Bufferable<Type>)
    }
    
    subscript(index: Int) -> Type {
            get {
                let bufferPointer = self.bufferPointer
                return bufferPointer[index+Int(self.offsetBytes/self.byteSize)]
            }
            set(newValue) {
                let bufferPointer = self.bufferPointer
                bufferPointer[index+Int(self.offsetBytes/self.byteSize)] = newValue
            }
        }
    func setVal(_ newValue: Type, at index: Int) {
        let bufferPointer = self.bufferPointer
        bufferPointer[index+Int(self.offsetBytes/self.byteSize)] = newValue
    }

}

class ScalarFloat: Bufferable<Float> {
    convenience init(value: Float) {
        self.init(shape: [1])
        self[0] = value;
    }
    
    convenience init(buffer: MTLBuffer, offset: Int = 0) {
        self.init(shape: [1], buffer: buffer, offset: offset)
    }
    
    var val : Float {self[0]}
    var intVal: Int16 {self.getInt(index: 0)}
    var long: Int {self.getLong(index: 0)}
}

let ScalarZero = ScalarFloat(value: 0)

class Scalar: Bufferable<Float16> {
    convenience init(value: Float16) {
        self.init(shape: [1])
        self[0] = value;
    }
    
    convenience init(buffer: MTLBuffer, offset: Int = 0) {
        self.init(shape: [1], buffer: buffer, offset: offset)
    }

    var val : Float16 {self[0]}
    var intVal: Int16 {self.getInt(index: 0)}

}


class Matrix: Bufferable<Float16> {
    var cols: Int { self.shape[1] }
    
    func TDimHack() {
        self.shape = [self.shape[1], self.shape[0]]
    }
    
    func asVector() -> Vector {
        return Vector(shape: [self.count], buffer: self.buffer, offset: self.offsetEls)
    }
    
    func scalarAt(_ row: Int, _ col: Int) -> Scalar {
        return Scalar(buffer: self.buffer, offset: self.offsetEls + row*self.cols + col)
    }
    
    func fetchRow(_ rowNum: ScalarFloat, out: VectorFloat) {
        assert (out.rows == self.cols)
        gpu.deploy("fetchRow16to32", buffers: [rowNum, self, out], threadCount: self.cols)
    }
    
    func asVectorList() -> [Vector] {
        var out = [Vector]()
        out.reserveCapacity(self.rows)
        for i in 0..<self.rows {
            out.append(Vector(shape:[self.cols], buffer:self.buffer, offset: self.offsetEls+i*self.cols))
        }
        return out
    }
    
    func ss(_ index: Int) -> Vector {
        return Vector(shape:[self.cols], buffer:self.buffer, offset: self.offsetEls+index*self.cols)
    }
    
    subscript(index: Int) -> Vector {
            get {
                Vector(shape:[self.cols], buffer:self.buffer, offset: self.offsetEls+index*self.cols)
            }
        }
    
    func sliced(numSlices: Int) -> Matrix3D {
        assert(self.rows % numSlices == 0)
        return Matrix3D(shape: [numSlices, self.rows/numSlices, self.cols], buffer: self.buffer, offset: self.offsetEls)
    }


}

class Matrix3DFloat: Bufferable<Float> {
    override var rows: Int { self.shape[1] }
    var cols: Int { self.shape[2] }
    var slices: Int { self.shape[0] }
//    var sliceSize: Int {self.rows * self.count}

    func asMatrixList() -> [MatrixFloat] {
        assert(self.shape.count == 3)
        var out = [MatrixFloat]()
        out.reserveCapacity(self.slices)
        for i in 0..<self.slices {
            out.append(MatrixFloat(shape:[shape[1], shape[2]], buffer:self.buffer, offset: self.offsetEls + i*self.shape[1]*self.shape[2]))
        }
        return out
    }
    
    subscript(index: Int) -> MatrixFloat {
            get {
                return MatrixFloat(shape:[shape[1], shape[2]], buffer:self.buffer, offset: self.offsetEls + index*self.shape[1]*self.shape[2])
            }
        }
}

class Matrix4DFloat: Bufferable<Float> {
    var cols: Int { self.shape[3] }
    override var rows: Int { self.shape[2] }
    var slices: Int { self.shape[1] }
    var sliceGroups: Int {self.shape[0]}

    func as3DMatrixList() -> [Matrix3DFloat] {
        assert(self.shape.count == 4)
        var out = [Matrix3DFloat]()
        out.reserveCapacity(self.sliceGroups)
        for i in 0..<self.sliceGroups {
            out.append(Matrix3DFloat(shape:[shape[1], shape[2], shape[3]], buffer:self.buffer, offset: self.offsetEls + i*self.shape[1]*self.shape[2]*self.shape[3]))
        }
        return out
    }
    
    subscript(index: Int) -> Matrix3DFloat {
            get {
                return Matrix3DFloat(shape:[shape[1], shape[2], shape[3]], buffer:self.buffer, offset: self.offsetEls + index*self.shape[1]*self.shape[2]*self.shape[3])
            }
        }
}

class Matrix3D: Bufferable<Float16> {
    override var rows: Int { self.shape[1] }
    var cols: Int { self.shape[2] }
    var slices: Int { self.shape[0] }
//    var sliceSize: Int {self.rows * self.count}

    func asMatrixList() -> [Matrix] {
        assert(self.shape.count == 3)
        var out = [Matrix]()
        out.reserveCapacity(self.slices)
        for i in 0..<self.slices {
            out.append(Matrix(shape:[shape[1], shape[2]], buffer:self.buffer, offset: self.offsetEls + i*self.shape[1]*self.shape[2]))
        }
        return out
    }
    
    subscript(index: Int) -> Matrix {
            get {
                return Matrix(shape:[shape[1], shape[2]], buffer:self.buffer, offset: self.offsetEls + index*self.shape[1]*self.shape[2])
            }
        }
}

private let _rms_mx = VectorFloat(shape: [numHeads])

class MatrixFloat: Bufferable<Float> {
    var cols: Int { self.shape[1] }

    func asVector() -> VectorFloat {
        return VectorFloat(shape: [self.count], buffer: self.buffer, offset: self.offsetEls)
    }
        
    func asVectorList() -> [VectorFloat] {
        var out = [VectorFloat]()
        out.reserveCapacity(self.rows)
        for i in 0..<self.rows {
            out.append(VectorFloat(shape:[self.cols], buffer:self.buffer, offset: self.offsetEls + i*self.cols))
        }
        return out
    }
    
    subscript(index: Int) -> VectorFloat {
            get {
                VectorFloat(shape:[self.cols], buffer:self.buffer, offset: self.offsetEls + index*self.cols)
            }
        }
    
    func scalarAt(_ row: Int, _ col: Int) -> ScalarFloat {
        return ScalarFloat(buffer: self.buffer, offset: self.offsetEls + row*self.cols + col)
    }

    func softmax() {
        _rms_mx.zero()
        gpu.deploy("sum_of_exps32_mx", buffers: [self, _rms_mx], ints: [self.cols], threadCount: [self.cols, numHeads])
        gpu.deploy("softmax_add32_mx", buffers: [self, _rms_mx], ints: [self.cols], threadCount: [self.cols, numHeads])
    }

    func mul(complexArray: VectorFloat) {
        assert(self.cols == complexArray.rows, "Layer size must be twice the size of the complex array")
        gpu.deploy("mulComplex32_mx", buffers: [self, complexArray], ints:[self.cols], threadCount: [self.cols / 2, self.rows])
    }
    
    func rope(complexArray: VectorFloat) {
        assert(self.cols*2 == complexArray.rows, "Layer size must be twice the size of the complex array")
        let out = MatrixFloat(shape:self.shape)
        gpu.deploy("rope_mx", buffers: [self, complexArray, out], ints:[self.cols], threadCount: [self.cols, self.rows])
        self.copyFrom(out)

    }

}

class DynaVectorFloat: VectorFloat {
    let size: ScalarFloat = ScalarFloat(value:0)
    
    func bins(binSize: Int) -> [Int] {
        gpu.eval()
        var bins = [Int](repeating: 0, count: 16)
        for i in 0..<Int(self.size.val) {
            bins[(Int(self[i*2+1]) % binSize * 16)/binSize] += 1
        }
        for i in 0..<16 {
            bins[i] = (bins[i]*100)/Int(self.size.val)
        }

        return bins
    }
}

let _normABuffer = ScalarFloat(value: 0)
let _normBBuffer = ScalarFloat(value: 0)
let _rms = ScalarFloat(value: 0.0)
let _dotBuffer = ScalarFloat(value:0)


class VectorFloat: Bufferable<Float> {
    
    func rmsNorm(out: VectorFloat) {
        out.zero()
        gpu.deploy("rmsNorm32", buffers: [self, out], threadCount: 4096)
    }

    func rmsNormFast(out: VectorFloat) {
        out.zero()
        gpu.deploy("rmsNorm32fast", buffers: [self, out], threadCount: 1024, threadGroupSize: [1024, 1, 1])
    }

    
    func cosineSimilarityTo(_ vec: VectorFloat) -> Float {
        _normABuffer.zero()
        _normBBuffer.zero()
        _dotBuffer.zero()
        gpu.deploy("cosinePrecalc32", buffers: [self, vec, _dotBuffer, _normABuffer, _normBBuffer], threadCount: self.rows)
        gpu.deploy("cosineCalc32", buffers: [_dotBuffer, _normABuffer, _normBBuffer], threadCount: 1)
        gpu.eval()
        return _dotBuffer[0]
    }

    func strictCompareTo(_ vec: VectorFloat) -> Bool {
        _normABuffer.zero()
        gpu.deploy("strictDiff32", buffers: [self, vec, _normABuffer], threadCount: self.rows)
        gpu.eval()
        return _normABuffer[0] == 0
    }
    
    func asFloat16() -> Vector {
        let out = Vector(shape:[self.rows])
        gpu.deploy("floatToHalf", buffers: [self, out], threadCount: self.rows)
        return out
    }
    
    
    func asMatrix(newCols: Int) -> MatrixFloat {
        assert(self.rows % newCols == 0, "Original layer size must be divisible by new dimension size")
        let newRows = self.rows / newCols

        return MatrixFloat(shape:[newRows, newCols], buffer: self.buffer, offset: self.offsetEls)
    }
    
    func reshaped(newCols: Int) -> [VectorFloat] {
        // Ensure that the original layer can be evenly divided by the new dimension size
        assert(self.rows % newCols == 0, "Original layer size must be divisible by new dimension size")
        
        let newRows = self.rows / newCols
        
        var out = [VectorFloat]()
        out.reserveCapacity(newRows)
        
        for i in 0..<newRows {
            out.append(VectorFloat(shape:[newCols], buffer:self.buffer, offset: i*newCols))
        }
        
        assert(out[1][0] == self[1*newCols])
        return out
    }
    
    func scalarAt(_ row: Int) -> ScalarFloat {
        return ScalarFloat(buffer: self.buffer, offset: row)
    }
    
    func rmsNormed() -> VectorFloat {
        let output = VectorFloat(shape: self.shape)
        gpu.deploy("rmsNorm32", buffers: [self, output], threadCount: self.count)

        return output
    }
    
    func softmax() {
        _rms.zero()
        gpu.deploy("sum_of_exps32", buffers: [self, _rms], threadCount: self.rows)
        gpu.deploy("softmax_add32", buffers: [self, _rms], threadCount: self.rows)
    }
    
    func mul(by wa: Vector) {
        assert(self.shape == wa.shape)
        gpu.deploy("mulVec32by16", buffers:[self, wa, self], threadCount:self.rows)
    }
    
    
    func repeated(_ count: Int) -> VectorFloat {
        assert(self.rows == 128*8)
        let output = VectorFloat(shape: [count*self.rows])
        gpu.deploy("repeat4x32", buffers: [self, output], threadCount: [128, 8])
        return output
    }

    func repeated(_ count: Int, into:VectorFloat) {
        assert(self.rows == 128*8)
        assert(into.rows == count*self.rows)
//        let output = VectorFloat(shape: [count*self.rows])
        gpu.deploy("repeat4x32", buffers: [self, into], threadCount: [128, 8])
//        return output
    }

    
}


class Vector: Bufferable<Float16> {
    func copy() -> Vector {
        let out = Vector(shape:self.shape)
        gpu.deploy("memcpy\(self.bitSize)", buffers: [self, out], threadCount: self.rows)
        return out
    }

    func asFloat32() -> VectorFloat {
        let out = VectorFloat(shape:[self.rows])
        gpu.deploy("halfToFloat", buffers: [self, out], threadCount: self.rows)
        return out
    }
    
    /*
    func cosineSimilarityTo(_ vec: Vector) -> ScalarFloat {
        let dotBuffer = ScalarFloat(value:0)
        _normABuffer.zero()
        _normBBuffer.zero()
        gpu.deploy("cosinePrecalc16", buffers: [self, vec, dotBuffer, _normABuffer, _normBBuffer], threadCount: self.rows)
        gpu.deploy("cosineCalc", buffers: [dotBuffer, _normABuffer, _normBBuffer], threadCount: 1)
        gpu.eval()
        return dotBuffer
    }*/
    
    func scalarAt(_ row: Int) -> Scalar {
        return Scalar(buffer: self.buffer, offset: row)
    }

    func copyFrom32(_ vec: VectorFloat) {
        assert(self.rows == vec.rows)
        gpu.deploy("floatToHalf", buffers: [vec, self], threadCount: self.rows)
    }
            
    func reshaped(newCols: Int) -> [Vector] {
        // Ensure that the original layer can be evenly divided by the new dimension size
        assert(self.rows % newCols == 0, "Original layer size must be divisible by new dimension size")
        
        let newRows = self.rows / newCols
        
        var out = [Vector]()
        out.reserveCapacity(newRows)
        
        for i in 0..<newRows {
            out.append(Vector(shape:[newCols], buffer:self.buffer, offset: i*newCols))
        }
        
        assert(out[1][0] == self[1*newCols])
        return out
    }
    

    func mul(by wa: Vector) {
        assert(self.shape == wa.shape)
        
        gpu.deploy("mulVec16by16", buffers:[self, wa, self], threadCount:self.rows)
    }
    
    func sort() {
        guard let logn = Int(exactly: log2(Double(self.rows))) else {
            fatalError("data.count is not a power of 2")
        }

        for p in 0..<logn {
            for q in 0..<p+1 {
                gpu.deploy("basicBitonicSort", buffers: [self], ints: [p, q], threadCount: self.rows)
            }
        }
    }
    
    
    func sortAbs(idxs: Vector) {
        assert(idxs.rows == self.rows)
  //      gpu.startCapture()

        guard let logn = Int(exactly: log2(Double(self.rows))) else {
            let l2 = Int(log2(Double(self.rows)))
            let paddedSize = Int(pow(Double(2), Double(l2+1)))
            let paddedSelf = Vector(shape: [paddedSize])
            paddedSelf.copyFrom(self, smallerSize: true)
            let paddedIdxs = Vector(shape: [paddedSize])
            paddedIdxs.copyFrom(idxs, smallerSize: true)
            
            paddedSelf.sortAbs(idxs: paddedIdxs)
            self.copyFrom(paddedSelf, smallerSize: true)
            idxs.copyFrom(paddedIdxs, smallerSize: true)
            return
        }

        for p in 0..<logn {
            for q in 0..<p+1 {
                gpu.deploy("idxsBitonicSortAbs", buffers: [self, idxs], ints: [p, q], threadCount: self.rows)
            }
        }
    }
    
}

/*
 
 array funcs
 
 */
/*

func createFreqsCis(headDim: Int, maxSeqLen: Int) -> [VectorFloat] {
    func logspace(start: Double, end: Double, num: Int, base: Double = 10.0) -> [Double] {
        assert(num>1)
        let step = (end - start) / Double(num)
        return (0..<num).map { pow(base, start + Double($0) * step) }
    }

    assert(headDim==128, "unusual headDim. it should work with others, but asserts/tests will fail")
    let freqs = logspace(start: 0, end: 1.0, num: headDim / 2, base: 1e-6)
//    assert(freqs[2] == 0.7498942093324559)
    let heads = MatrixFloat(shape: [2*maxSeqLen, freqs.count*2]).asVectorList()
    for i in 0..<(2 * maxSeqLen) {
        for j in 0..<freqs.count {
            let freq = freqs[j]
            let angle = Float(i) * Float(freq)
            let realPart = cos(angle)
            let imagPart = sin(angle)
            heads[i][j*2] = realPart
            heads[i][j*2+1] = imagPart
        }
    }
    /*
    assert(heads[1][2]==0.6479058)
    assert(heads[1][3]==0.7617204)
     */
    return heads
}
*/

func createFreqsCis2(headDim: Int, maxSeqLen: Int) -> [VectorFloat] {
    func logspace(start: Double, end: Double, num: Int, base: Double = 10.0) -> [Double] {
        assert(num>1)
        let step = (end - start) / Double(num)
        return (0..<num).map { pow(base, start + Double($0) * step) }
    }

    assert(headDim==128, "unusual headDim. it should work with others, but asserts/tests will fail")
    let freqs = logspace(start: 0, end: 1.0, num: headDim/2, base: 1e-6)
//    assert(freqs[2] == 0.7498942093324559)
    let heads = MatrixFloat(shape: [2*maxSeqLen, freqs.count*2*2]).asVectorList()
    for i in 0..<(2 * maxSeqLen) {
        for j in 0..<freqs.count*2 {
            let freq = freqs[j % (freqs.count)]
            let angle = Float(i) * Float(freq)
            let realPart = cos(angle)
            let imagPart = sin(angle)
            heads[i][j*2] = realPart
            heads[i][j*2+1] = imagPart
        }
    }
  //  assert(heads[1][2]==0.6479058)
  //  assert(heads[1][3]==0.7617204)
    return heads
}

func createFreqsCis(headDim: Int, maxSeqLen: Int) -> [VectorFloat] {
    func logspace(start: Double, end: Double, num: Int, base: Double = 10.0) -> [Double] {
        assert(num>1)
        let step = (end - start) / Double(num)
        return (0..<num).map { pow(base, start + Double($0) * step) }
    }

    assert(headDim==128, "unusual headDim. it should work with others, but asserts/tests will fail")
    let freqs = logspace(start: 0, end: 1.0, num: headDim / 2, base: 1e-6)
    let heads = MatrixFloat(shape: [2*maxSeqLen, freqs.count*2]).asVectorList()
    for i in 0..<(2 * maxSeqLen) {
        for j in 0..<freqs.count {
            let freq = freqs[j]
            let angle = Float(i) * Float(freq)
            let realPart = cos(angle)
            let imagPart = sin(angle)
            heads[i][j*2] = realPart
            heads[i][j*2+1] = imagPart
        }
    }
    return heads
}

func calcScores(xq_heads: MatrixFloat, xkTokenHeads: Matrix3DFloat, numTokens: Int, out scores: MatrixFloat) {
    gpu.deploy("dotSetScore2",
               buffers: [xq_heads, xkTokenHeads, scores],
               threadCount: [128, numTokens, numHeads],
               threadGroupSize: [128, 1, 1])
    
}


func gpuConsolidate(vecList src:[VectorFloat]) -> MatrixFloat {
    assert(src.count > 0)

    let out = MatrixFloat(shape:[src.count, src[0].rows])
    let outVecs = out.asVectorList()
    
    for i in 0..<src.count {
        outVecs[i].copyFrom(src[i])
    }

    return out
}

func sumScores2(numHeads: Int, headDim:Int, scores: MatrixFloat, xvToken: MatrixFloat, numTokens: Int) -> VectorFloat {
    let outMatrix = MatrixFloat(shape: [numHeads, headDim])
    let numDims = numHeads*headDim
    
    assert(scores.cols == numTokens)
    
    gpu.deploy("sumScores32", buffers:[scores, xvToken, outMatrix], ints: [numTokens], threadCount: [numDims])
    
    return outMatrix.asVector()
}

func sumScores(scores: MatrixFloat, xvToken: MatrixFloat, numTokens: Int, out: VectorFloat) {
    let numDims = numHeads*headDim
    
    assert(scores.cols == numTokens)
    out.zero()
    gpu.deploy("sumScores32", buffers:[scores, xvToken, out], ints: [numTokens, scores.cols], threadCount: [numDims])
    
}

func silu(_ x1: Vector, _ x3: Vector, out: Vector) {
    gpu.deploy("silu", buffers: [x1, x3, out], threadCount: x1.rows)
}

func silu(_ x1: VectorFloat, _ x3: VectorFloat, out: VectorFloat) {
    gpu.deploy("silu32b", buffers: [x1, x3, out], threadCount: x1.rows/64)
}
