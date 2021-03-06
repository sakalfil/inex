require 'test_helper'

class EventCategoriesControllerTest < ActionController::TestCase
  setup do
    @event_category = event_categories(:one)
    session[:user_id] = users(:one).id
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:event_categories)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create event_category" do
    assert_difference('EventCategory.count') do
      post :create, event_category: { abbr: @event_category.abbr, name: @event_category.name }
    end

    assert_redirected_to event_categories_path
  end

  test "should get edit" do
    get :edit, id: @event_category
    assert_response :success
  end

  test "should update event_category" do
    patch :update, id: @event_category, event_category: { abbr: @event_category.abbr, name: @event_category.name }
    assert_redirected_to event_categories_path
  end

  test "should destroy event_category" do
    assert_difference('EventCategory.count', -1) do
      delete :destroy, id: @event_category
    end

    assert_redirected_to event_categories_path
  end
end
