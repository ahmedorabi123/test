import { Component, type ErrorInfo, type ReactNode } from "react";

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  error: Error | null;
}

export default class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // Surface render-time exceptions instead of leaving a blank screen.
    console.error("[ErrorBoundary]", error, info.componentStack);
  }

  reset = () => this.setState({ error: null });

  render() {
    if (!this.state.error) return this.props.children;
    if (this.props.fallback) return this.props.fallback;

    return (
      <div className="mx-auto max-w-2xl p-6">
        <div className="rounded-xl border border-rose-200 bg-rose-50 p-6">
          <h1 className="text-lg font-semibold text-rose-800">
            Something went wrong on this page.
          </h1>
          <p className="mt-2 text-sm text-rose-700">
            {this.state.error.message ||
              "An unexpected error occurred while rendering."}
          </p>
          <div className="mt-4 flex gap-2">
            <button
              type="button"
              onClick={this.reset}
              className="rounded-lg border border-rose-300 px-3 py-1.5 text-sm font-medium text-rose-800 hover:bg-rose-100"
            >
              Try again
            </button>
            <button
              type="button"
              onClick={() => {
                this.reset();
                window.location.assign("/");
              }}
              className="rounded-lg bg-rose-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-rose-700"
            >
              Go to dashboard
            </button>
          </div>
        </div>
      </div>
    );
  }
}
