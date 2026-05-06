@foo class A {}
@foo() class B {}
@foo @bar @baz.qux class C {}
@foo.bar class D {}
@foo.bar.baz({ a: 1, b: [1, 2] }) class E {}
@foo<T>() class F {}
@foo abstract class G {}
