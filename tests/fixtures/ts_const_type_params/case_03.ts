function f<const T = "x">(x: T): T { return x; }
function g<const T extends string = "default">(x: T): T { return x; }
