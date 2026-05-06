class X {
    @foo method() {}
    @foo prop: number = 1;
    @foo() public bar: string;
    @foo @bar.factory() async qux(): Promise<void> {}
    @foo get name(): string { return ''; }
    @foo set value(v: T) {}
}
