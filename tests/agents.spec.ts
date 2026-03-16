// Tests for the Agents tab view.
// Uses a fake token to bypass login without real API calls.

import { test, expect } from "@playwright/test";

test.describe("Agents tab", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    // Inject a fake token to get past the login form.
    // API calls will fail silently but UI renders.
    await page.evaluate(() => {
      localStorage.setItem(
        "gh-dashboard-token",
        "ghp_fake_for_testing"
      );
    });
    await page.reload();
    // Wait for the app to initialize
    await page.waitForSelector(".toolbar");
  });

  test("Agents tab button exists", async ({ page }) => {
    await expect(
      page.locator(".tab-btn", { hasText: "Agents" })
    ).toBeVisible();
  });

  test("Agents tab is first in tab bar", async ({
    page,
  }) => {
    const tabs = page.locator(".tab-btn");
    const firstTab = tabs.first();
    await expect(firstTab).toHaveText("Agents");
  });

  test("clicking Agents tab shows agents view", async ({
    page,
  }) => {
    await page
      .locator(".tab-btn", { hasText: "Agents" })
      .click();
    await expect(
      page.locator(".agents-view")
    ).toBeVisible();
  });

  test("Agents view shows session header", async ({
    page,
  }) => {
    await page
      .locator(".tab-btn", { hasText: "Agents" })
      .click();
    await expect(
      page.locator("text=Agent Sessions")
    ).toBeVisible();
  });

  test("Agents view shows empty state without agent server", async ({
    page,
  }) => {
    await page
      .locator(".tab-btn", { hasText: "Agents" })
      .click();
    await expect(
      page.locator(".agents-empty")
    ).toBeVisible();
  });

  test("Agents view has refresh button", async ({
    page,
  }) => {
    await page
      .locator(".tab-btn", { hasText: "Agents" })
      .click();
    await expect(
      page.locator(".agents-title-row .btn-hide")
    ).toBeVisible();
  });

  test("tab switching preserves state", async ({
    page,
  }) => {
    // Switch to Agents
    await page
      .locator(".tab-btn", { hasText: "Agents" })
      .click();
    await expect(
      page.locator(".agents-view")
    ).toBeVisible();

    // Switch to Repos
    await page
      .locator(".tab-btn", { hasText: "Repos" })
      .click();
    await expect(
      page.locator(".agents-view")
    ).not.toBeVisible();

    // Switch back to Agents
    await page
      .locator(".tab-btn", { hasText: "Agents" })
      .click();
    await expect(
      page.locator(".agents-view")
    ).toBeVisible();
  });

  test("Agents tab persists across reload", async ({
    page,
  }) => {
    // Switch to Agents
    await page
      .locator(".tab-btn", { hasText: "Agents" })
      .click();
    await expect(
      page.locator(".agents-view")
    ).toBeVisible();

    // Reload page
    await page.reload();
    await page.waitForSelector(".toolbar");

    // Should still be on Agents tab
    await expect(
      page.locator(".agents-view")
    ).toBeVisible();
    await expect(
      page.locator(".tab-btn.active", {
        hasText: "Agents",
      })
    ).toBeVisible();
  });
});
