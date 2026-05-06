type Push<T extends any[], U> = [...T, U];
type Cons<H, T extends any[]> = [H, ...T];
type Triple = [string, ...number[]];
