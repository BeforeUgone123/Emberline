const { test, expect } = require('playwright/test');

const previewUrl =
  'file:///mnt/linux_share/preview/harmony-advanced-terminal/' +
  'docs/frontend-brainstorm/2026-07-18-harmonyos-ui-ux-optimization/preview/index.html';

test('default view is a terminal-first workspace', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(previewUrl);

  await expect(page.locator('#appShell')).not.toHaveClass(/inspector-open/);
  await expect(page.locator('#terminal')).toBeVisible();
  await expect(page.locator('.app-actions > .icon-button')).toHaveCount(3);
  await expect(page.getByRole('button', { name: '新建终端会话' })).toBeVisible();

  const geometry = await page.evaluate(() => {
    const tabZone = document.querySelector('.tab-zone').getBoundingClientRect();
    const actions = document.querySelector('.app-actions').getBoundingClientRect();
    const controls = document.querySelector('.window-controls').getBoundingClientRect();
    return {
      viewportWidth: window.innerWidth,
      documentWidth: document.documentElement.scrollWidth,
      tabRight: tabZone.right,
      actionsLeft: actions.left,
      actionsRight: actions.right,
      controlsLeft: controls.left
    };
  });
  expect(geometry.documentWidth).toBe(geometry.viewportWidth);
  expect(geometry.tabRight).toBeLessThanOrEqual(geometry.actionsLeft + 0.5);
  expect(geometry.actionsRight).toBeLessThanOrEqual(geometry.controlsLeft + 0.5);
});

test('inspector, tabs, focus return, and transient menu are interactive', async ({ page }) => {
  await page.setViewportSize({ width: 960, height: 820 });
  await page.goto(previewUrl);

  await page.getByRole('button', { name: '连接', exact: true }).click();
  await expect(page.locator('#appShell')).toHaveClass(/inspector-open/);
  await page.getByRole('tab', { name: '终端', exact: true }).click();
  await expect(page.locator('#terminal-pane')).toHaveClass(/active/);

  await page.getByRole('button', { name: '增大字号' }).click();
  await expect(page.locator('#fontSizeValue')).toHaveText('14');
  await expect(page.locator('#terminal')).toHaveCSS('font-size', '14px');

  await page.keyboard.press('Escape');
  await expect(page.locator('#appShell')).not.toHaveClass(/inspector-open/);
  await expect(page.locator('#terminal')).toBeFocused();

  await page.getByRole('button', { name: '更多' }).click();
  await expect(page.locator('#moreMenu')).toHaveClass(/open/);
  await page.getByRole('menuitem', { name: '关于 Emberline' }).click();
  await expect(page.locator('#toast')).toContainText('Emberline Dev');

  await page.getByRole('button', { name: '新建终端会话' }).click();
  await expect(page.locator('.tab')).toHaveCount(4);
});

for (const viewport of [
  { width: 720, height: 820, inspectorWidth: 352 },
  { width: 960, height: 820, inspectorWidth: 400 },
  { width: 1440, height: 900, inspectorWidth: 400 }
]) {
  test(`connection inspector fits ${viewport.width}px viewport`, async ({ page }) => {
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await page.goto(`${previewUrl}?inspector=connection`);
    await expect(page.locator('#appShell')).toHaveClass(/inspector-open/);
    await page.waitForTimeout(250);

    const geometry = await page.evaluate(() => {
      const panel = document.querySelector('#inspector').getBoundingClientRect();
      const actions = document.querySelector('.app-actions').getBoundingClientRect();
      const controls = document.querySelector('.window-controls').getBoundingClientRect();
      return {
        viewportWidth: window.innerWidth,
        documentWidth: document.documentElement.scrollWidth,
        panelWidth: panel.width,
        panelRight: panel.right,
        actionsRight: actions.right,
        controlsLeft: controls.left
      };
    });
    expect(geometry.documentWidth).toBe(geometry.viewportWidth);
    expect(geometry.panelWidth).toBe(viewport.inspectorWidth);
    expect(geometry.panelRight).toBe(viewport.width);
    expect(geometry.actionsRight).toBeLessThanOrEqual(geometry.controlsLeft + 0.5);
  });
}

test('reconnect motion is state-bound and settles', async ({ page }) => {
  await page.setViewportSize({ width: 960, height: 820 });
  await page.goto(`${previewUrl}?inspector=connection`);

  await page.getByRole('button', { name: '重新连接' }).click();
  await expect(page.locator('#statusBand')).toHaveClass(/pending/);
  await expect(page.locator('#connectionStatus')).toContainText('正在连接');
  await expect(page.getByRole('button', { name: '连接中' })).toBeDisabled();

  await expect(page.locator('#statusBand')).not.toHaveClass(/pending/, { timeout: 2500 });
  await expect(page.locator('#connectionStatus')).toContainText('已连接');
  await expect(page.getByRole('button', { name: '重新连接' })).toBeEnabled();
});
