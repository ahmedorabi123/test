/* eslint-disable @typescript-eslint/no-explicit-any */
import { render, type RenderOptions } from "@testing-library/react";
import { combineReducers, configureStore } from "@reduxjs/toolkit";
import { Provider } from "react-redux";
import { MemoryRouter } from "react-router-dom";
import type { ReactElement, ReactNode } from "react";
import authReducer from "../store/slices/authSlice";

interface RenderOpts extends Omit<RenderOptions, "wrapper"> {
  route?: string;
  preloadedState?: any;
}

const rootReducer = combineReducers({ auth: authReducer });

export function makeStore(preloadedState?: any) {
  return configureStore({
    reducer: rootReducer,
    preloadedState,
  });
}

export function renderWithProviders(
  ui: ReactElement,
  { route = "/", preloadedState, ...rest }: RenderOpts = {}
) {
  const store = makeStore(
    preloadedState ?? {
      auth: {
        user: {
          id: "u1",
          email: "admin@example.com",
          first_name: "Ad",
          last_name: "Min",
          roles: ["admin"],
          permissions: [],
        },
        token: "test-token",
        loading: false,
        error: null,
      },
    }
  );

  function Wrapper({ children }: { children: ReactNode }) {
    return (
      <Provider store={store}>
        <MemoryRouter initialEntries={[route]}>{children}</MemoryRouter>
      </Provider>
    );
  }

  return { store, ...render(ui, { wrapper: Wrapper, ...rest }) };
}
