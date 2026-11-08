document.documentElement.dataset.micaExtension = 'active';
browser.runtime.sendMessage({kind: 'mica-check'}).then(response => {
    document.documentElement.dataset.micaExtensionReply = response.ok ? 'ok' : 'no-tab';
}).catch(error => { document.documentElement.dataset.micaExtensionReply = String(error); });
