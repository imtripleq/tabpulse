// Copy buttons: the label says what happened ("Copied"), and a live region says it too.

const RESET_MS = 2000;

async function writeText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }
  // Fallback for plain-http previews: select a hidden textarea and copy it.
  const area = document.createElement('textarea');
  area.value = text;
  area.setAttribute('readonly', '');
  area.className = 'sr-only';
  document.body.append(area);
  area.select();
  const ok = document.execCommand('copy');
  area.remove();
  if (!ok) throw new Error('copy command was refused');
}

export function initCopy() {
  const status = document.querySelector('#copy-status');
  document.querySelectorAll('[data-copy]').forEach((button) => {
    const source = document.getElementById(button.dataset.copy);
    if (!source) return;
    const label = button.textContent;
    let timer = 0;
    button.addEventListener('click', async () => {
      clearTimeout(timer);
      try {
        await writeText(source.textContent.trim());
        button.textContent = 'Copied';
        button.classList.add('is-copied');
        if (status) status.textContent = `${label.replace(/^Copy /, '')} copied.`.replace(/^./, (c) => c.toUpperCase());
      } catch {
        button.textContent = 'Copy failed';
        if (status) status.textContent = 'Copying failed. Select the command and copy it yourself.';
      }
      timer = setTimeout(() => {
        button.textContent = label;
        button.classList.remove('is-copied');
      }, RESET_MS);
    });
  });
}
