// Bridge to the native host (Mica.App). The host owns every piece of browser state and sends it here as one
// snapshot whenever it changes; the shell draws it and sends commands back. Nothing here talks to the network.
//
//   shell to host:  { name, args }                       a command (see ShellCommands.cs)
//                   { name, args, id }                   a request that expects a reply
//   host to shell:  { type: "state", state }             the whole window state
//                   { type: "reply", id, result }        answer to a request
//                   { type: "event", name, args }        one-off signals: focus the address, open a menu
//
// Without WebView2 (the page opened in an ordinary browser during development) dev/mock-host.js stands in.

const webview = window.chrome && window.chrome.webview;
const listeners = { state: [], event: [] };
const waiting = new Map();
let sequence = 0;
let transport = null;

export function connect(mock) {
  if (webview) {
    transport = message => webview.postMessage(message);
    webview.addEventListener('message', event => receive(event.data));
  } else if (mock) {
    transport = message => mock.receive(message);
    mock.attach(receive);
  } else throw new Error('no host');
}

function receive(message) {
  if (!message || typeof message !== 'object') return;
  if (message.type === 'state') for (const fn of listeners.state) fn(message.state);
  else if (message.type === 'reply') {
    const resolve = waiting.get(message.id);
    if (resolve) { waiting.delete(message.id); resolve(message.result); }
  } else if (message.type === 'event') for (const fn of listeners.event) fn(message.name, message.args || {});
}

export function onState(fn) { listeners.state.push(fn); }
export function onEvent(fn) { listeners.event.push(fn); }

export function send(name, args) { transport({ name, args: args || {} }); }

export function request(name, args) {
  const id = ++sequence;
  return new Promise(resolve => {
    waiting.set(id, resolve);
    transport({ name, args: args || {}, id });
  });
}

export const hosted = !!webview;
