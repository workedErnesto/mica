browser.runtime.onMessage.addListener((message, sender, reply) => {
    if (message.kind !== 'mica-check') return false;
    browser.storage.local.set({lastCheck: true}).then(() => reply({ok: !!sender.tab}));
    return true;
});
