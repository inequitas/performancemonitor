public extension Array {
    /// Moves the element at `index` one position towards the beginning of the array.
    /// Has no effect if `index` is out of bounds or if the element is already at the first position.
    mutating func moveUp(at index: Int) {
        guard index > 0, index < count else { return }
        swapAt(index, index - 1)
    }

    /// Moves the element at `index` one position towards the end of the array.
    /// Has no effect if `index` is out of bounds or if the element is already at the last position.
    mutating func moveDown(at index: Int) {
        guard index >= 0, index < count - 1 else { return }
        swapAt(index, index + 1)
    }
}
