class X {
    method(@foo x: number) {}
    ctor(@foo x: number, @bar.dec() y: string) {}
    fn(@foo public p: T, q: U) {}
    multi(@d1 @d2.factory() x: T) {}
}
