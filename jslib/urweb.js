function sr(v) { return {v : v} }
function sb(x,y) { return {v : y(x.v).v} }

function dyn(s) {
  var x = document.createElement("span");
  x.innerHTML = s.v;
  document.body.appendChild(x);
}