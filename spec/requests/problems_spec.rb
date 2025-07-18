require "rails_helper"

# problems GET    /problems(.:format)                                                     problems#index
#  problem PATCH  /problems/:id(.:format)                                                 problems#update

RSpec.describe "Problems" do
  context "when signed out" do
    it "needs testing when multiuser is enabled"
  end

  context "when signed in" do
    describe "GET /problems", :as_contributor do
      it "is denied to contributors" do
        get "/problems/index"
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "GET /problems", :as_moderator do
      before do
        create_list(:problem, 2, category: :inefficient)
        create_list(:problem_on_model, 3, category: :missing)
      end

      it "returns success" do
        get "/problems/index"
        expect(response).to have_http_status(:success)
      end

      it "lists problems" do
        get "/problems/index"
        expect(assigns(:problems).length).to eq 5
      end

      context "with silenced problems" do
        before do
          u = User.first
          u.problem_settings["missing"] = "silent"
          u.save!
          sign_in u
        end

        it "doesn't show problems with silent severity" do
          get "/problems/index"
          expect(assigns(:problems).length).to eq 2
        end
      end

      context "when filtering by category" do
        it "only shows selected categories" do
          get "/problems/index", params: {"category[]": "missing"}
          expect(assigns(:problems).length).to eq 3
        end

        it "can show more than one category" do
          get "/problems/index", params: {"category[]": ["missing", "inefficient"]}
          expect(assigns(:problems).length).to eq 5
        end
      end

      context "when filtering by object type" do
        it "only shows selected types" do
          get "/problems/index", params: {"type[]": "model"}
          expect(assigns(:problems).length).to eq 3
        end

        it "can show more than one type" do
          get "/problems/index", params: {"type[]": ["model", "model_file"]}
          expect(assigns(:problems).length).to eq 5
        end
      end

      context "when filtering by severity" do
        it "only shows selected severities" do
          get "/problems/index", params: {"severity[]": "info"}
          expect(assigns(:problems).length).to eq 2
        end

        it "can show more than one severity" do
          get "/problems/index", params: {"severity[]": ["danger", "info"]}
          expect(assigns(:problems).length).to eq 5
        end
      end

      context "when filtering by severity AND category" do
        it "only shows the intersection of both" do
          get "/problems/index", params: {"category[]": ["missing"], "severity[]": ["danger", "info"]}
          expect(assigns(:problems).length).to eq 3
        end
      end
    end

    describe "PATCH /problems/:id" do
      let(:problem) { create(:problem) }

      before { patch "/problems/#{problem.to_param}", params: {problem: {ignored: true}} }

      it "updates the problem and returns to list", :as_moderator do
        expect(response).to redirect_to("/problems")
      end

      it "is denied to non-moderators", :as_contributor do
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
