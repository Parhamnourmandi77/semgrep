
function test1() {
    myArray = tainted;
    myArray.forEach((x) => {
        foobar()
        //ruleid: test
        sink(x)
     })
}

function test2() {
    myArray = [tainted];
    myArray.forEach((x) => {
        foobar()
        //ruleid: test
        sink(x)
     })
}